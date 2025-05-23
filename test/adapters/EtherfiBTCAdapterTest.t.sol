// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {EtherfiBTCAdapter} from "../../contracts/adapters/etherfi/EtherfiBTCAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {IAtomicQueue} from "../../contracts/adapters/etherfi/interfaces/IAtomicQueue.sol";
import {ILiquidityPool} from "../../contracts/adapters/etherfi/interfaces/ILiquidityPool.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

interface IWithdrawRequestNFTAdmin {
    function finalizeRequests(uint256 requestId) external;
    function nextRequestId() external view returns (uint256);
    function isFinalized(uint256 requestId) external view returns (bool);
    function isValid(uint256 requestId) external view returns (bool);
    function getClaimableAmount(uint256 requestId) external view returns (uint256);
}

interface IAtomicSolver {
    function redeemSolve(
        address queue,
        IERC20 offer,
        IERC20 want,
        address[] calldata users,
        uint256 minimumAssetsOut,
        uint256 maxAssets,
        address teller
    ) external;
}

contract EtherfiBTCAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 private constant EBTC = IERC20(0x657e8C867D8B37dCC18fA4Caead9C45EB088C642);
    address private constant LAYER_ZERO_TELLER = 0x6Ee3aaCcf9f2321E49063C4F8da775DdBd407268;
    address private constant ATOMIC_QUEUE = 0xD45884B592E316eB816199615A95C182F75dea07;
    IAtomicSolver private constant ATOMIC_SOLVER = IAtomicSolver(0x989468982b08AEfA46E37CD0086142A86fa466D7);
    address private constant SOLVER_ADMIN = 0xf8553c8552f906C19286F21711721E206EE4909E;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    EtherfiBTCAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(WBTC), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(EBTC), address(USDC));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, USDC, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new EtherfiBTCAdapter(address(WBTC), address(EBTC), LAYER_ZERO_TELLER, ATOMIC_QUEUE);
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(WBTC), address(levvaVault), 10 * 10 ** 8);

        levvaVault.addTrackedAsset(address(EBTC));
        levvaVault.addTrackedAsset(address(WBTC));
    }

    function testDepositBtc() public {
        uint256 wbtcBalanceBefore = WBTC.balanceOf(address(levvaVault));
        uint256 depositAmount = 10 ** 8;
        vm.prank(address(levvaVault));
        adapter.depositBtc(depositAmount);

        assertEq(wbtcBalanceBefore - WBTC.balanceOf(address(levvaVault)), depositAmount);
        assertApproxEqAbs(EBTC.balanceOf(address(levvaVault)), depositAmount, 1);
        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), 0);
    }

    function testDepositBtcNotTrackedAssets() public {
        levvaVault.removeTrackedAsset(address(EBTC));

        uint256 depositAmount = 10 ** 8;
        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, EBTC));
        adapter.depositBtc(depositAmount);
    }

    function testRequestWithdrawBtc() public {
        uint256 depositAmount = 2 * 10 ** 8;
        vm.prank(address(levvaVault));
        adapter.depositBtc(depositAmount);

        uint88 price = 10 ** 8;
        uint64 deadline = type(uint64).max;
        uint256 withdrawAmount = depositAmount;

        vm.prank(address(levvaVault));
        adapter.requestWithdrawBtc(uint96(withdrawAmount), price, deadline);

        IAtomicQueue.AtomicRequest memory request =
            IAtomicQueue(ATOMIC_QUEUE).getUserAtomicRequest(address(adapter), EBTC, WBTC);

        assertEq(request.deadline, deadline);
        assertEq(request.atomicPrice, price);
        assertEq(request.offerAmount, depositAmount);
        assert(!request.inSolve);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), depositAmount);

        address[] memory users = new address[](1);
        users[0] = address(adapter);

        vm.prank(SOLVER_ADMIN);
        ATOMIC_SOLVER.redeemSolve(ATOMIC_QUEUE, EBTC, WBTC, users, 0, type(uint256).max, LAYER_ZERO_TELLER);

        uint256 expectedBalance = withdrawAmount.mulDiv(price, 10 ** 8);
        assertEq(WBTC.balanceOf(address(adapter)), expectedBalance);
        assertEq(EBTC.balanceOf(address(adapter)), 0);
    }

    function testRequestWithdrawBtcNotTrackedAsset() public {
        uint256 depositAmount = WBTC.balanceOf(address(levvaVault));
        vm.prank(address(levvaVault));
        adapter.depositBtc(depositAmount);

        levvaVault.removeTrackedAsset(address(WBTC));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, WBTC));
        adapter.requestWithdrawBtc(uint96(depositAmount), 10 ** 8, type(uint64).max);
    }

    function testCancelWithdrawBtc() public {
        uint256 depositAmount = 10 ** 8;
        vm.prank(address(levvaVault));
        adapter.depositBtc(depositAmount);

        vm.prank(address(levvaVault));
        adapter.requestWithdrawBtc(uint96(depositAmount), 10 ** 8, type(uint64).max);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), depositAmount);

        vm.prank(address(levvaVault));
        adapter.cancelWithdrawBtcRequest();

        IAtomicQueue.AtomicRequest memory request =
            IAtomicQueue(ATOMIC_QUEUE).getUserAtomicRequest(address(adapter), EBTC, WBTC);

        assertEq(request.deadline, 0);
        assertEq(request.atomicPrice, 0);
        assertEq(request.offerAmount, 0);
        assert(!request.inSolve);

        assertEq(EBTC.allowance(address(adapter), ATOMIC_QUEUE), 0);
    }
}
