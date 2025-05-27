// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {IStakedUSDe} from "../../contracts/adapters/ethena/interfaces/IStakedUSDe.sol";
import {EthenaAdapter} from "../../contracts/adapters/ethena/EthenaAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

interface IStakedUSDeAdmin {
    function setCooldownDuration(uint24 duration) external;
    function owner() external view returns (address);
}

contract EthenaAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IStakedUSDe private constant S_USDE = IStakedUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IERC20 private constant USDE = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);

    address private NO_ACCESS = makeAddr("NO_ACCESS");

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    EthenaAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDE), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(117, 100), address(S_USDE), address(USDC));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, USDC, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new EthenaAdapter(address(levvaVault), address(S_USDE));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDE), address(levvaVault), 10 ** 12);

        levvaVault.addTrackedAsset(address(USDE));
        levvaVault.addTrackedAsset(address(S_USDE));
    }

    function testSetup() public view {
        assertEq(address(adapter.stakedUSDe()), address(S_USDE));
        assertEq(adapter.USDe(), address(USDE));
    }

    function testDeposit() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(usdeBalanceBefore - USDE.balanceOf(address(levvaVault)), depositAmount);
        assertEq(S_USDE.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0);
    }

    function testDepositNotTrackedAsset() public {
        levvaVault.removeTrackedAsset(address(S_USDE));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, S_USDE));
        adapter.deposit(1000 * 10 ** 6);
    }

    function testCooldown() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.cooldownShares(expectedLpTokens);

        assertEq(USDE.balanceOf(address(levvaVault)), usdeBalanceBefore - depositAmount);
        assertEq(S_USDE.balanceOf(address(levvaVault)), 0);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(S_USDE.convertToAssets(expectedLpTokens));
    }

    function testCooldownOnlyVault() public {
        vm.prank(address(NO_ACCESS));
        vm.expectRevert(abi.encodeWithSelector(EthenaAdapter.NoAccess.selector));
        adapter.cooldownShares(1000);
    }

    function testUnstake() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.cooldownShares(expectedLpTokens);

        skip(S_USDE.cooldownDuration());

        vm.prank(address(levvaVault));
        adapter.unstake();

        assertApproxEqAbs(USDE.balanceOf(address(levvaVault)), usdeBalanceBefore, 1);
        assertEq(S_USDE.balanceOf(address(levvaVault)), 0);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0);
    }

    function testUnstakeOnlyVault() public {
        vm.prank(address(NO_ACCESS));
        vm.expectRevert(abi.encodeWithSelector(EthenaAdapter.NoAccess.selector));
        adapter.unstake();
    }

    function testUnstakeNotTrackedAsset() public {
        uint256 depositAmount = USDE.balanceOf(address(levvaVault));
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.cooldownShares(expectedLpTokens);

        skip(S_USDE.cooldownDuration());

        levvaVault.removeTrackedAsset(address(USDE));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, USDE));
        adapter.unstake();
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(IStakedUSDeAdmin(address(S_USDE)).owner());
        IStakedUSDeAdmin(address(S_USDE)).setCooldownDuration(0);

        vm.prank(address(levvaVault));
        adapter.redeem(expectedLpTokens);

        assertApproxEqAbs(USDE.balanceOf(address(levvaVault)), usdeBalanceBefore, 1);
        assertEq(S_USDE.balanceOf(address(levvaVault)), 0);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0);
    }

    function testRedeemNotTrackedAsset() public {
        uint256 depositAmount = USDE.balanceOf(address(levvaVault));
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(IStakedUSDeAdmin(address(S_USDE)).owner());
        IStakedUSDeAdmin(address(S_USDE)).setCooldownDuration(0);

        levvaVault.removeTrackedAsset(address(USDE));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, USDE));
        adapter.redeem(expectedLpTokens);
    }

    function _assertAdapterAssets(uint256 expectedUsde) private {
        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(USDE));
        assertEq(amounts[0], expectedUsde);

        (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(USDE));
        assertEq(amounts[0], expectedUsde);

        _assertNoDebtAssets();
    }

    function _assertNoDebtAssets() private {
        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }
}
