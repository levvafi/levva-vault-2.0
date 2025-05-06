// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {LevvaVault} from "../contracts/LevvaVault.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {FeeCollector} from "../contracts/base/FeeCollector.sol";
import {MintableERC20} from "./mocks/MintableERC20.t.sol";
import {EulerRouterMock} from "./mocks/EulerRouterMock.t.sol";

contract FeeCollectorTest is Test {
    using Math for uint256;

    uint256 constant ONE = 1_000_000;

    LevvaVault public levvaVaultImplementation;
    ERC1967Proxy public levvaVaultProxy;
    LevvaVault public levvaVault;

    MintableERC20 public asset = new MintableERC20("USDTest", "USDTest", 6);

    EulerRouterMock oracle = new EulerRouterMock();

    string lpName = "lpName";
    string lpSymbol = "lpSymbol";

    address noAccess = address(0xDEAD);
    address feeCollector = address(0xFEE);
    address user = address(0x987654321);

    uint48 fee = 100_000; // 10%
    uint256 depositAmount = 10_000_000;

    function setUp() public {
        levvaVaultImplementation = new LevvaVault();
        bytes memory data =
            abi.encodeWithSelector(LevvaVault.initialize.selector, IERC20(asset), lpName, lpSymbol, feeCollector, address(oracle));
        levvaVaultProxy = new ERC1967Proxy(address(levvaVaultImplementation), data);
        levvaVault = LevvaVault(address(levvaVaultProxy));

        asset.mint(user, 2 * depositAmount);
        vm.prank(user);
        asset.approve(address(levvaVault), 2 * depositAmount);
        vm.prank(user);
        levvaVault.deposit(depositAmount, user);
    }

    function testManagementFee() public {
        levvaVault.setManagementFeeIR(fee);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        skip(365 days);

        uint256 toRedeem = levvaVault.maxRedeem(user);
        vm.prank(user);
        levvaVault.redeem(toRedeem, user, user);

        uint256 feeCollectorAssets = totalAssetsBefore.mulDiv(fee, ONE);

        assertEq(levvaVault.getFeeCollectorStorage().lastFeeTimestamp, block.timestamp);
        assertEq(levvaVault.totalAssets(), feeCollectorAssets);
        assertEq(levvaVault.maxWithdraw(feeCollector), feeCollectorAssets);

        vm.prank(user);
        levvaVault.deposit(depositAmount, user);
        skip(365 days);

        toRedeem = levvaVault.maxRedeem(user);
        vm.prank(user);
        levvaVault.redeem(toRedeem, user, user);

        feeCollectorAssets += depositAmount.mulDiv(fee, ONE);

        assertEq(levvaVault.getFeeCollectorStorage().lastFeeTimestamp, block.timestamp);
        assertEq(levvaVault.totalAssets(), feeCollectorAssets);
        assertEq(levvaVault.maxWithdraw(feeCollector), feeCollectorAssets);
    }

    function testPerformanceFeeIncrease() public {
        levvaVault.setPerformanceFeeRatio(fee);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        asset.mint(address(levvaVault), totalAssetsBefore);

        uint256 toRedeem = levvaVault.maxRedeem(user);
        vm.prank(user);
        levvaVault.redeem(toRedeem, user, user);

        assertEq(levvaVault.totalAssets(), totalAssetsBefore.mulDiv(fee, ONE));
        assertApproxEqAbs(levvaVault.getFeeCollectorStorage().highWaterMarkPerShare, 2 * 10 ** levvaVault.decimals(), 1);
    }

    function testPerformanceFeeDecrease() public {
        levvaVault.setPerformanceFeeRatio(fee);

        uint256 totalAssetsBefore = levvaVault.totalAssets();
        asset.burn(address(levvaVault), totalAssetsBefore / 2);

        uint256 toRedeem = levvaVault.maxRedeem(user);
        vm.prank(user);
        levvaVault.redeem(toRedeem, user, user);

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
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, noAccess));
        vm.prank(noAccess);
        levvaVault.setFeeCollector(noAccess);
    }

    function testSetFeeCollectorSameValue() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setFeeCollector(feeCollector);
    }

    function testSetFeeCollectorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        levvaVault.setFeeCollector(address(0));
    }

    function testSetManagementFeeIR() public {
        vm.expectEmit(address(levvaVault));
        emit FeeCollector.ManagementFeeIRSet(fee);

        levvaVault.setManagementFeeIR(fee);
        assertEq(levvaVault.getFeeCollectorStorage().managementFeeIR, fee);
    }

    function testSetManagementFeeIROnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, noAccess));
        vm.prank(noAccess);
        levvaVault.setManagementFeeIR(fee);
    }

    function testSetManagementFeeIRSameValue() public {
        levvaVault.setManagementFeeIR(fee);
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setManagementFeeIR(fee);
    }

    function testSetPerformanceFeeRatio() public {
        vm.expectEmit(address(levvaVault));
        emit FeeCollector.PerformanceFeeRatioSet(fee);

        levvaVault.setPerformanceFeeRatio(fee);
        assertEq(levvaVault.getFeeCollectorStorage().performanceFeeRatio, fee);
    }

    function testSetPerformanceFeeRatioOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, noAccess));
        vm.prank(noAccess);
        levvaVault.setPerformanceFeeRatio(fee);
    }

    function testSetPerformanceFeeRatioSameValue() public {
        levvaVault.setPerformanceFeeRatio(fee);
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setPerformanceFeeRatio(fee);
    }
}
