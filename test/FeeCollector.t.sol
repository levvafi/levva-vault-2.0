// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {FeeCollector} from "../contracts/base/FeeCollector.sol";

contract FeeCollectorTest is TestSetUp {
    using Math for uint256;

    uint256 constant ONE = 1_000_000;
    uint48 constant FEE = 100_000; // 10%
    uint256 constant DEPOSIT_AMOUNT = 10_000_000;

    function setUp() public override {
        super.setUp();

        asset.mint(USER, 2 * DEPOSIT_AMOUNT);
        vm.prank(USER);
        asset.approve(address(levvaVault), 2 * DEPOSIT_AMOUNT);
        vm.prank(USER);
        levvaVault.deposit(DEPOSIT_AMOUNT, USER);
    }

    function testManagementFee() public {
        levvaVault.setManagementFeeIR(FEE);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        skip(365 days);

        uint256 toRedeem = levvaVault.maxRedeem(USER);
        vm.prank(USER);
        levvaVault.redeem(toRedeem, USER, USER);

        uint256 feeCollectorAssets = totalAssetsBefore.mulDiv(FEE, ONE);

        assertEq(levvaVault.getFeeCollectorStorage().lastFeeTimestamp, block.timestamp);
        assertEq(levvaVault.totalAssets(), feeCollectorAssets);
        assertEq(levvaVault.maxWithdraw(FEE_COLLECTOR), feeCollectorAssets);

        vm.prank(USER);
        levvaVault.deposit(DEPOSIT_AMOUNT, USER);
        skip(365 days);

        toRedeem = levvaVault.maxRedeem(USER);
        vm.prank(USER);
        levvaVault.redeem(toRedeem, USER, USER);

        feeCollectorAssets += DEPOSIT_AMOUNT.mulDiv(FEE, ONE);

        assertEq(levvaVault.getFeeCollectorStorage().lastFeeTimestamp, block.timestamp);
        assertEq(levvaVault.totalAssets(), feeCollectorAssets);
        assertEq(levvaVault.maxWithdraw(FEE_COLLECTOR), feeCollectorAssets);
    }

    function testPerformanceFeeIncrease() public {
        levvaVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        asset.mint(address(levvaVault), totalAssetsBefore);

        uint256 toRedeem = levvaVault.maxRedeem(USER);
        uint256 expectedAssets = levvaVault.convertToAssets(toRedeem);
        vm.prank(USER);
        uint256 assets = levvaVault.redeem(toRedeem, USER, USER);

        assertEq(expectedAssets, assets);
        assertEq(levvaVault.totalAssets(), totalAssetsBefore.mulDiv(FEE, ONE));
        assertApproxEqAbs(levvaVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** levvaVault.decimals(), 1);
    }

    function testPreviewMintWithFee() public {
        levvaVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        asset.mint(address(levvaVault), totalAssetsBefore);

        uint256 toMint = 10 ** levvaVault.decimals();
        uint256 expectedAssets = levvaVault.previewMint(toMint);
        assertApproxEqAbs(levvaVault.convertToAssets(toMint), expectedAssets, 1);

        vm.prank(USER);
        uint256 assets = levvaVault.mint(toMint, USER);

        assertEq(expectedAssets, assets);
        assertApproxEqAbs(levvaVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** levvaVault.decimals(), 1);
    }

    function testPreviewDepositWithFee() public {
        levvaVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        asset.mint(address(levvaVault), totalAssetsBefore);

        uint256 toDeposit = 10 ** asset.decimals();
        uint256 expectedShares = levvaVault.previewDeposit(toDeposit);
        assertApproxEqAbs(levvaVault.convertToShares(toDeposit), expectedShares, 1);

        vm.prank(USER);
        uint256 shares = levvaVault.deposit(toDeposit, USER);

        assertEq(expectedShares, shares);
        assertApproxEqAbs(levvaVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** levvaVault.decimals(), 1);
    }

    function testPreviewRedeemWithFee() public {
        levvaVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        asset.mint(address(levvaVault), totalAssetsBefore);

        uint256 toRedeem = levvaVault.maxRedeem(USER);
        uint256 expectedAssets = levvaVault.previewRedeem(toRedeem);
        assertApproxEqAbs(levvaVault.convertToAssets(toRedeem), expectedAssets, 1);

        vm.prank(USER);
        uint256 assets = levvaVault.redeem(toRedeem, USER, USER);

        assertEq(expectedAssets, assets);
        assertEq(levvaVault.totalAssets(), totalAssetsBefore.mulDiv(FEE, ONE));
        assertApproxEqAbs(levvaVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** levvaVault.decimals(), 1);
    }

    function testPreviewWithdrawWithFee() public {
        levvaVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        asset.mint(address(levvaVault), totalAssetsBefore);

        uint256 toWithdraw = levvaVault.maxWithdraw(USER);
        uint256 expectedShares = levvaVault.previewWithdraw(toWithdraw);
        assertApproxEqAbs(levvaVault.convertToShares(toWithdraw), expectedShares, 1);

        vm.prank(USER);
        uint256 shares = levvaVault.withdraw(toWithdraw, USER, USER);

        assertEq(expectedShares, shares);
        assertEq(levvaVault.totalAssets(), totalAssetsBefore.mulDiv(FEE, ONE));
        assertApproxEqAbs(levvaVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** levvaVault.decimals(), 1);
    }

    function testPerformanceFeeDecrease() public {
        levvaVault.setPerformanceFeeRatio(FEE);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        asset.burn(address(levvaVault), totalAssetsBefore / 2);

        uint256 toRedeem = levvaVault.maxRedeem(USER);
        vm.prank(USER);
        levvaVault.redeem(toRedeem, USER, USER);

        assertEq(levvaVault.totalAssets(), 0);
    }

    function testSetFeeCollector() public {
        address newFeeCollector = address(0xFEE2);
        vm.expectEmit(address(levvaVault));
        emit FeeCollector.FeeCollectorSet(newFeeCollector);

        levvaVault.setFeeCollector(newFeeCollector);
        assertEq(levvaVault.getFeeCollectorStorage().feeCollector, newFeeCollector);
    }

    function testSetFeeCollectorOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        levvaVault.setFeeCollector(NO_ACCESS);
    }

    function testSetFeeCollectorSameValue() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setFeeCollector(FEE_COLLECTOR);
    }

    function testSetFeeCollectorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        levvaVault.setFeeCollector(address(0));
    }

    function testSetManagementFeeIR() public {
        vm.expectEmit(address(levvaVault));
        emit FeeCollector.ManagementFeeIRSet(FEE);

        levvaVault.setManagementFeeIR(FEE);
        assertEq(levvaVault.getFeeCollectorStorage().managementFeeIR, FEE);
    }

    function testSetManagementFeeIROnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        levvaVault.setManagementFeeIR(FEE);
    }

    function testSetManagementFeeIRSameValue() public {
        levvaVault.setManagementFeeIR(FEE);
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setManagementFeeIR(FEE);
    }

    function testSetPerformanceFeeRatio() public {
        vm.expectEmit(address(levvaVault));
        emit FeeCollector.PerformanceFeeRatioSet(FEE);

        levvaVault.setPerformanceFeeRatio(FEE);
        assertEq(levvaVault.getFeeCollectorStorage().performanceFeeRatio, FEE);
    }

    function testSetPerformanceFeeRatioOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
        levvaVault.setPerformanceFeeRatio(FEE);
    }

    function testSetPerformanceFeeRatioSameValue() public {
        levvaVault.setPerformanceFeeRatio(FEE);
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setPerformanceFeeRatio(FEE);
    }
}
