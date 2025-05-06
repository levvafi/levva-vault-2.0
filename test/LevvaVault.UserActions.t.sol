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
