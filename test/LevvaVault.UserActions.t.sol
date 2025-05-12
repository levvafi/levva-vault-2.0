// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {MultiAssetVaultBase} from "../contracts/base/MultiAssetVaultBase.sol";
import {WithdrawalRequestQueue} from "../contracts/base/WithdrawalRequestQueue.sol";

contract LevvaVaultUserActionsTest is TestSetUp {
    uint256 constant MIN_DEPOSIT = 1_000_000;

    function setUp() public override {
        super.setUp();
        asset.mint(USER, 10 * MIN_DEPOSIT);

        levvaVault.addAdapter(address(externalPositionAdapter));
    }

    function testTotalAssets() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        uint256 depositAmount = 10 ** 12;
        asset.mint(address(this), depositAmount);
        asset.approve(address(levvaVault), depositAmount);
        levvaVault.deposit(depositAmount, address(this));

        assertEq(levvaVault.totalAssets(), depositAmount);

        uint256 trackedAssetAmount = 1_000 * 10 ** 18;
        trackedAsset.mint(address(levvaVault), trackedAssetAmount);

        uint256 expectedTotalAssets =
            depositAmount + oracle.getQuote(trackedAssetAmount, address(trackedAsset), address(asset));
        assertEq(levvaVault.totalAssets(), expectedTotalAssets);
    }

    function testDeposit() public {
        levvaVault.setMinimalDeposit(MIN_DEPOSIT);
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT);

        vm.prank(USER);
        levvaVault.deposit(MIN_DEPOSIT, USER);
    }

    function testLessThanMinDeposit() public {
        levvaVault.setMinimalDeposit(MIN_DEPOSIT);
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT - 1);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.LessThanMinDeposit.selector, MIN_DEPOSIT));
        levvaVault.deposit(MIN_DEPOSIT - 1, USER);
    }

    function testZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAmount.selector));
        levvaVault.deposit(0, USER);
    }

    function testMint() public {
        levvaVault.setMinimalDeposit(MIN_DEPOSIT);
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT);

        vm.prank(USER);
        levvaVault.mint(MIN_DEPOSIT, USER);
    }

    function testLessThanMinDepositMint() public {
        levvaVault.setMinimalDeposit(MIN_DEPOSIT);
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT - 1);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.LessThanMinDeposit.selector, MIN_DEPOSIT));
        levvaVault.mint(MIN_DEPOSIT - 1, USER);
    }

    function testZeroAmountMint() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAmount.selector));
        levvaVault.mint(0, USER);
    }

    function testEnqueueWithdrawal() public {
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT);

        vm.prank(USER);
        levvaVault.deposit(MIN_DEPOSIT, USER);
        assertEq(levvaVault.balanceOf(USER), MIN_DEPOSIT);

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](1);
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(
            externalPositionAdapter.deposit.selector, address(asset), MIN_DEPOSIT / 2, MIN_DEPOSIT / 2, 0
        );
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: externalPositionAdapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });
        vm.prank(VAULT_MANAGER);
        levvaVault.executeAdapterAction(args);
        assertEq(oracle.getQuote(MIN_DEPOSIT / 2, address(asset), address(externalPositionManagedAsset)), MIN_DEPOSIT / 2);
        assertEq(levvaVault.totalAssets(), MIN_DEPOSIT);

        uint256 assetBalanceBefore = asset.balanceOf(USER);
        uint256 lpBalanceBefore = levvaVault.balanceOf(USER);
        address receiver = address(0x1);

        vm.prank(USER);
        levvaVault.withdraw(MIN_DEPOSIT, receiver, USER);

        assertEq(asset.balanceOf(USER), assetBalanceBefore);
        assertEq(levvaVault.balanceOf(USER), 0);
        assertEq(levvaVault.balanceOf(address(levvaVault)), lpBalanceBefore);

        WithdrawalRequestQueue.WithdrawalRequest memory request = levvaVault.withdrawalRequest(0);
        assertEq(request.receiver, receiver);
        assertEq(request.shares, lpBalanceBefore);
    }
}
