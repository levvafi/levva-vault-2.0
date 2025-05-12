// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {MultiAssetVaultBase} from "../contracts/base/MultiAssetVaultBase.sol";

contract LevvaVaultUserActionsTest is TestSetUp {
    uint256 constant MIN_DEPOSIT = 1_000_000;

    function setUp() public override {
        super.setUp();
        levvaVault.setMinimalDeposit(MIN_DEPOSIT);
        asset.mint(USER, 10 * MIN_DEPOSIT);
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
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT);

        vm.prank(USER);
        levvaVault.deposit(MIN_DEPOSIT, USER);
    }

    function testLessThanMinDeposit() public {
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT - 1);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.LessThanMinDeposit.selector, MIN_DEPOSIT));
        levvaVault.deposit(MIN_DEPOSIT - 1, USER);
    }

    function testZeroAmount() public {
        levvaVault.setMinimalDeposit(0);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAmount.selector));
        levvaVault.deposit(0, USER);
    }

    function testMint() public {
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT);

        vm.prank(USER);
        levvaVault.mint(MIN_DEPOSIT, USER);
    }

    function testLessThanMinDepositMint() public {
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT - 1);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.LessThanMinDeposit.selector, MIN_DEPOSIT));
        levvaVault.mint(MIN_DEPOSIT - 1, USER);
    }

    function testZeroAmountMint() public {
        levvaVault.setMinimalDeposit(0);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAmount.selector));
        levvaVault.mint(0, USER);
    }
}
