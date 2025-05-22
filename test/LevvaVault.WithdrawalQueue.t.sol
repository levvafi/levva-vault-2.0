// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {VaultAccessControl} from "../contracts/base/VaultAccessControl.sol";
import {WithdrawalRequestQueue} from "../contracts/base/WithdrawalRequestQueue.sol";

contract LevvaVaultUserActionsTest is TestSetUp {
    uint256 constant MIN_DEPOSIT = 1_000_000;

    function setUp() public override {
        super.setUp();
        asset.mint(USER, 10 * MIN_DEPOSIT);

        levvaVault.addAdapter(address(externalPositionAdapter),"");
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
        assertEq(
            oracle.getQuote(MIN_DEPOSIT / 2, address(asset), address(externalPositionManagedAsset)), MIN_DEPOSIT / 2
        );
        assertEq(levvaVault.totalAssets(), MIN_DEPOSIT);

        uint256 assetBalanceBefore = asset.balanceOf(USER);
        uint256 lpBalanceBefore = levvaVault.balanceOf(USER);
        address receiver = address(0x1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(levvaVault),
                asset.balanceOf(address(levvaVault)),
                MIN_DEPOSIT
            )
        );
        vm.prank(USER);
        levvaVault.withdraw(MIN_DEPOSIT, receiver, USER);

        vm.prank(USER);
        levvaVault.requestWithdrawal(MIN_DEPOSIT, receiver, USER);

        assertEq(asset.balanceOf(USER), assetBalanceBefore);
        assertEq(levvaVault.balanceOf(USER), 0);
        assertEq(levvaVault.balanceOf(address(levvaVault)), lpBalanceBefore);

        WithdrawalRequestQueue.WithdrawalRequest memory request = levvaVault.withdrawalRequest(0);
        assertEq(request.receiver, receiver);
        assertEq(request.shares, lpBalanceBefore);
    }

    function testRequestWithdrawalSufficientBalance() public {
        vm.prank(USER);
        asset.approve(address(levvaVault), MIN_DEPOSIT);

        vm.prank(USER);
        levvaVault.deposit(MIN_DEPOSIT, USER);
        assertEq(levvaVault.balanceOf(USER), MIN_DEPOSIT);

        address receiver = address(0x1);
        vm.prank(USER);
        levvaVault.requestWithdrawal(MIN_DEPOSIT, receiver, USER);

        assertEq(asset.balanceOf(receiver), MIN_DEPOSIT);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalRequestQueue.NoElementWithIndex.selector, 0));
        levvaVault.withdrawalRequest(0);
    }

    function testFinalizeWithdrawal() public {
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

        address receiver = address(0x1);

        vm.prank(USER);
        levvaVault.requestWithdrawal(MIN_DEPOSIT, receiver, USER);

        adapterCalldataWithSelector = abi.encodeWithSelector(
            externalPositionAdapter.withdraw.selector, address(asset), MIN_DEPOSIT / 2, MIN_DEPOSIT / 2, 0
        );
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: externalPositionAdapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });
        vm.prank(VAULT_MANAGER);
        levvaVault.executeAdapterAction(args);

        vm.prank(VAULT_MANAGER);
        levvaVault.finalizeWithdrawalRequest();

        assertEq(asset.balanceOf(receiver), MIN_DEPOSIT);
        assertEq(levvaVault.balanceOf(address(levvaVault)), 0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalRequestQueue.NoElementWithIndex.selector, 0));
        levvaVault.withdrawalRequest(0);
    }

    function testFinalizeWithdrawalNotEnoughBalance() public {
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

        address receiver = address(0x1);

        vm.prank(USER);
        levvaVault.requestWithdrawal(MIN_DEPOSIT, receiver, USER);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(levvaVault),
                asset.balanceOf(address(levvaVault)),
                MIN_DEPOSIT
            )
        );
        vm.prank(VAULT_MANAGER);
        levvaVault.finalizeWithdrawalRequest();
    }

    function testFinalizeOnlyRole() public {
        vm.expectRevert(abi.encodeWithSelector(VaultAccessControl.NoAccess.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        levvaVault.finalizeWithdrawalRequest();
    }
}
