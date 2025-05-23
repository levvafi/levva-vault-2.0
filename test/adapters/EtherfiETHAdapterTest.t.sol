// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {EtherfiETHAdapter} from "../../contracts/adapters/etherfi/EtherfiETHAdapter.sol";
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

contract EtherfiETHAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    address private constant ETHERFI_ADMIN = 0xcD425f44758a08BaAB3C4908f3e3dE5776e45d7a;
    ILiquidityPool private constant ETHERFI_LIQUIDITY_POOL = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IERC20 private eETH;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    EtherfiETHAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        eETH = IERC20(ETHERFI_LIQUIDITY_POOL.eETH());

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(2000, 10 ** 12), address(WETH), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(2000, 10 ** 12), address(eETH), address(USDC));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, USDC, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new EtherfiETHAdapter(address(WETH), address(ETHERFI_LIQUIDITY_POOL));
        levvaVault.addAdapter(address(adapter));
        assertNotEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(WETH), address(levvaVault), 10 ether);

        levvaVault.addTrackedAsset(address(eETH));
        levvaVault.addTrackedAsset(address(WETH));
    }

    function testDepositEth() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));

        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertApproxEqAbs(eETH.balanceOf(address(levvaVault)), depositAmount, 1);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eETH.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        _assertNoDebtAssets();
    }

    function testDepositEthNotTrackedAsset() public {
        levvaVault.removeTrackedAsset(address(eETH));

        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, eETH));
        adapter.deposit(depositAmount);
    }

    function testRequestWithdrawEth() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        uint256 requestId = adapter.requestWithdraw(depositAmount);

        IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
        assertEq(requestId, nft.nextRequestId() - 1);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertEq(eETH.balanceOf(address(levvaVault)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eETH.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertApproxEqAbs(amounts[0], depositAmount, 1);

        (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertApproxEqAbs(amounts[0], depositAmount, 1);

        _assertNoDebtAssets();
    }

    function testClaimWithdrawEth() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.requestWithdraw(depositAmount);

        IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
        uint256 lastRequest = nft.nextRequestId() - 1;
        vm.prank(ETHERFI_ADMIN);
        nft.finalizeRequests(lastRequest);

        vm.prank(address(levvaVault));
        adapter.claimWithdraw();

        assertApproxEqAbs(WETH.balanceOf(address(levvaVault)), wethBalanceBefore, 1);
        assertEq(eETH.balanceOf(address(levvaVault)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eETH.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        _assertNoDebtAssets();
    }

    function testClaimWithdrawEthNotFinalized() public {
        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.requestWithdraw(depositAmount);

        vm.prank(address(levvaVault));
        vm.expectRevert("Request is not finalized");
        adapter.claimWithdraw();
    }

    function testClaimNoRequests() public {
        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(EtherfiETHAdapter.NoWithdrawRequestInQueue.selector));
        adapter.claimWithdraw();
    }

    function testClaimEthNotTrackedAsset() public {
        uint256 depositAmount = WETH.balanceOf(address(levvaVault));
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.requestWithdraw(depositAmount);

        IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
        uint256 lastRequest = nft.nextRequestId() - 1;
        vm.prank(ETHERFI_ADMIN);
        nft.finalizeRequests(lastRequest);

        levvaVault.removeTrackedAsset(address(WETH));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, WETH));
        adapter.claimWithdraw();
    }

    function _assertNoDebtAssets() private {
        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }
}
