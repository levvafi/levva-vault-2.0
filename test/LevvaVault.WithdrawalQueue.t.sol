// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {VaultAccessControl} from "../contracts/base/VaultAccessControl.sol";
import {WithdrawalQueue} from "../contracts/WithdrawalQueue.sol";

contract LevvaVaultUserActionsTest is TestSetUp {
    uint256 constant MIN_DEPOSIT = 1_000_000;

    function setUp() public override {
        super.setUp();
        asset.mint(USER, 10 * MIN_DEPOSIT);

        levvaVault.addAdapter(address(externalPositionAdapter));
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

        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(MIN_DEPOSIT);
        assertEq(requestId, 1);

        assertEq(asset.balanceOf(USER), assetBalanceBefore);
        assertEq(levvaVault.balanceOf(USER), 0);
        assertEq(levvaVault.balanceOf(address(withdrawalQueue)), lpBalanceBefore);
        assertEq(withdrawalQueue.ownerOf(requestId), USER);

        WithdrawalQueue.WithdrawalRequest memory request = withdrawalQueue.getWithdrawalRequest(requestId);
        assertEq(request.shares, lpBalanceBefore);
        assertEq(request.assets, MIN_DEPOSIT);
    }

    function testClaimWithdrawal() public {
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

        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(MIN_DEPOSIT);

        adapterCalldataWithSelector = abi.encodeWithSelector(
            externalPositionAdapter.withdraw.selector, address(asset), MIN_DEPOSIT / 2, MIN_DEPOSIT / 2, 0
        );
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: externalPositionAdapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });
        vm.prank(VAULT_MANAGER);
        levvaVault.executeAdapterAction(args);

        withdrawalQueue.finalizeRequests(requestId);
        uint256 userBalanceBefore = asset.balanceOf(USER);

        vm.prank(USER);
        withdrawalQueue.claimWithdrawal(requestId);

        assertEq(asset.balanceOf(USER) - userBalanceBefore, MIN_DEPOSIT);
        assertEq(levvaVault.balanceOf(address(withdrawalQueue)), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, requestId));
        withdrawalQueue.ownerOf(requestId);
    }

    // function testFinalizeOnlyRole() public {
    //     vm.expectRevert(abi.encodeWithSelector(VaultAccessControl.NoAccess.selector, NO_ACCESS));
    //     vm.prank(NO_ACCESS);
    //     levvaVault.finalizeWithdrawalRequest();
    // }
}
