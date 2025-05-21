// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {EtherfiAdapter} from "../../contracts/adapters/etherfi/EtherfiAdapter.sol";
import {ILiquidityPool} from "../../contracts/adapters/etherfi/interfaces/ILiquidityPool.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

interface IWithdrawRequestNFTAdmin {
    function finalizeRequests(uint256 requestId) external;
    function nextRequestId() external view returns (uint256);
    function isFinalized(uint256 requestId) external view returns (bool);
    function isValid(uint256 requestId) external view returns (bool);
}

contract EtherfiAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    address ETHERFI_ADMIN = 0xcD425f44758a08BaAB3C4908f3e3dE5776e45d7a;
    ILiquidityPool private constant ETHERFI_LIQUIDITY_POOL = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private eEth;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    EtherfiAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        eEth = IERC20(ETHERFI_LIQUIDITY_POOL.eETH());

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(eEth), address(WETH));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, WETH, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new EtherfiAdapter(address(WETH), address(ETHERFI_LIQUIDITY_POOL));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(WETH), address(levvaVault), 10 ether);

        levvaVault.addTrackedAsset(address(eEth));
    }

    function testDepositEth() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));

        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertApproxEqAbs(eEth.balanceOf(address(levvaVault)), depositAmount, 1);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eEth.balanceOf(address(adapter)), 0);
    }

    function testRequestWithdrawEth() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.requestWithdraw(depositAmount);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertEq(eEth.balanceOf(address(levvaVault)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eEth.balanceOf(address(adapter)), 0);
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
        assertEq(eEth.balanceOf(address(levvaVault)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eEth.balanceOf(address(adapter)), 0);
    }
}
