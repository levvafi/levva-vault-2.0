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
import {WithdrawalQueueBase} from "../contracts/base/WithdrawalQueueBase.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract LevvaWithdrawalQueueTest is TestSetUp {
    uint256 constant DEPOSIT = 1_000_000;

    function setUp() public override {
        super.setUp();
        asset.mint(USER, 10 * DEPOSIT);

        vm.prank(USER);
        asset.approve(address(levvaVault), DEPOSIT);

        vm.prank(USER);
        levvaVault.deposit(DEPOSIT, USER);
        assertEq(levvaVault.balanceOf(USER), DEPOSIT);
    }

    function testRequestWithdrawal() public {
        uint256 assetBalanceBefore = asset.balanceOf(USER);
        uint256 lpBalanceBefore = levvaVault.balanceOf(USER);

        uint256 withdrawalAmount = DEPOSIT / 2;
        uint256 lpBalanceDelta = levvaVault.previewWithdraw(withdrawalAmount);

        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(withdrawalAmount);
        assertEq(requestId, 1);
        assertEq(withdrawalQueue.lastRequestId(), 1);

        assertEq(asset.balanceOf(USER), assetBalanceBefore);
        assertEq(lpBalanceBefore - levvaVault.balanceOf(USER), lpBalanceDelta);
        assertEq(levvaVault.balanceOf(address(withdrawalQueue)), lpBalanceDelta);
        assertEq(withdrawalQueue.ownerOf(requestId), USER);

        uint256 requestedShares = withdrawalQueue.getRequestedShares(requestId);
        assertEq(requestedShares, lpBalanceDelta);
    }

    function testRequestWithdrawalExceedsMax() public {
        uint256 lpBalance = levvaVault.balanceOf(USER);
        uint256 maxWithdraw = levvaVault.convertToAssets(lpBalance);
        uint256 exceedsMaxWithdraw = maxWithdraw + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Upgradeable.ERC4626ExceededMaxWithdraw.selector, USER, exceedsMaxWithdraw, maxWithdraw
            )
        );
        vm.prank(USER);
        levvaVault.requestWithdrawal(exceedsMaxWithdraw);
    }

    function testDirectPoolWithdrawFail() public {
        vm.expectRevert(abi.encodeWithSelector(VaultAccessControl.NoAccess.selector, USER));
        vm.prank(USER);
        levvaVault.withdraw(DEPOSIT, USER, USER);
    }

    function testRequestRedeem() public {
        uint256 assetBalanceBefore = asset.balanceOf(USER);
        uint256 lpBalanceBefore = levvaVault.balanceOf(USER);

        uint256 lpBalanceDelta = lpBalanceBefore / 2;

        vm.prank(USER);
        uint256 requestId = levvaVault.requestRedeem(lpBalanceDelta);
        assertEq(requestId, 1);

        assertEq(asset.balanceOf(USER), assetBalanceBefore);
        assertEq(lpBalanceBefore - levvaVault.balanceOf(USER), lpBalanceDelta);
        assertEq(levvaVault.balanceOf(address(withdrawalQueue)), lpBalanceDelta);
        assertEq(withdrawalQueue.ownerOf(requestId), USER);

        uint256 requestedShares = withdrawalQueue.getRequestedShares(requestId);
        assertEq(requestedShares, lpBalanceDelta);
    }

    function testRequestRedeemExceedsMax() public {
        uint256 maxRedeem = levvaVault.balanceOf(USER);
        uint256 exceedsMaxRedeem = maxRedeem + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector, USER, exceedsMaxRedeem, maxRedeem
            )
        );
        vm.prank(USER);
        levvaVault.requestRedeem(exceedsMaxRedeem);
    }

    function testDirectPoolRedeemFail() public {
        vm.expectRevert(abi.encodeWithSelector(VaultAccessControl.NoAccess.selector, USER));
        vm.prank(USER);
        levvaVault.redeem(DEPOSIT, USER, USER);
    }

    function testRequestOnlyVault() public {
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueBase.NoAccess.selector, USER));
        vm.prank(USER);
        withdrawalQueue.requestWithdrawal(DEPOSIT, USER);
    }

    function testClaimWithdrawal() public {
        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(DEPOSIT);

        vm.prank(FINALIZER);
        withdrawalQueue.finalizeRequests(requestId);
        assertEq(withdrawalQueue.lastFinalizedRequestId(), 1);

        uint256 userBalanceBefore = asset.balanceOf(USER);
        vm.prank(USER);
        withdrawalQueue.claimWithdrawal(requestId);

        assertEq(asset.balanceOf(USER) - userBalanceBefore, DEPOSIT);
        assertEq(levvaVault.balanceOf(address(withdrawalQueue)), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, requestId));
        withdrawalQueue.ownerOf(requestId);

        uint256 requestedShares = withdrawalQueue.getRequestedShares(requestId);
        assertEq(requestedShares, 0);
    }

    function testClaimWithdrawalNotFinalized() public {
        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(DEPOSIT);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.NotFinalized.selector));
        vm.prank(USER);
        withdrawalQueue.claimWithdrawal(requestId);
    }

    function testClaimWithdrawalNotRequestOwner() public {
        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(DEPOSIT);

        vm.prank(FINALIZER);
        withdrawalQueue.finalizeRequests(requestId);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.NotRequestOwner.selector));
        vm.prank(NO_ACCESS);
        withdrawalQueue.claimWithdrawal(requestId);
    }

    function testFinalizeOnlyFinalizer() public {
        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(DEPOSIT);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueBase.NoAccess.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        withdrawalQueue.finalizeRequests(requestId);
    }

    function testFinalizeAlreadyFinalized() public {
        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(DEPOSIT);

        vm.prank(FINALIZER);
        withdrawalQueue.finalizeRequests(requestId);

        vm.prank(FINALIZER);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueBase.AlreadyFinalized.selector));
        withdrawalQueue.finalizeRequests(requestId);
    }

    function testFinalizeFutureFinalization() public {
        vm.prank(USER);
        uint256 requestId = levvaVault.requestWithdrawal(DEPOSIT);

        vm.prank(FINALIZER);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueueBase.FutureFinalization.selector));
        withdrawalQueue.finalizeRequests(requestId + 1);
    }

    function testAddFinalizerNoAccess() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        withdrawalQueue.addFinalizer(NO_ACCESS, true);
    }
}
