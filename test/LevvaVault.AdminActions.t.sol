// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {MultiAssetVaultBase} from "../contracts/base/MultiAssetVaultBase.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {VaultAccessControl} from "../contracts/base/VaultAccessControl.sol";
import {OraclePriceProvider} from "../contracts/base/OraclePriceProvider.sol";
import {MintableERC20} from "./mocks/MintableERC20.t.sol";
import {EulerRouterMock} from "./mocks/EulerRouterMock.t.sol";

contract LevvaVaultAdminActionsTest is TestSetUp {
    function testAddNewAsset() public {
        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 0);

        vm.expectEmit(address(levvaVault));
        emit MultiAssetVaultBase.NewTrackedAssetAdded(address(trackedAsset), 1);
        levvaVault.addTrackedAsset(address(trackedAsset));

        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 1);
        assertEq(levvaVault.trackedAssetsCount(), 1);
    }

    function testAddNewAssetOnlyOwner() public {
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        levvaVault.addTrackedAsset(address(trackedAsset));
    }

    function testAddNewAssetAlreadyTracked() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                MultiAssetVaultBase.AlreadyTracked.selector, levvaVault.trackedAssetPosition(address(trackedAsset))
            )
        );
        levvaVault.addTrackedAsset(address(trackedAsset));
    }

    function testAddNewAssetExceedsLimit() public {
        levvaVault.setMaxTrackedAssets(0);

        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.ExceedsTrackedAssetsLimit.selector));
        levvaVault.addTrackedAsset(address(trackedAsset));
    }

    function testAddNewAssetZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        levvaVault.addTrackedAsset(address(0));
    }

    function testAddNewAssetOracleNotExist() public {
        MintableERC20 secondTrackedAsset = new MintableERC20("wstUSDTest", "wstUSDTest", 6);
        vm.expectRevert(
            abi.encodeWithSelector(
                OraclePriceProvider.OracleNotExist.selector, address(secondTrackedAsset), levvaVault.asset()
            )
        );
        levvaVault.addTrackedAsset(address(secondTrackedAsset));
    }

    function testRemoveLastAsset() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        vm.expectEmit(address(levvaVault));
        emit MultiAssetVaultBase.TrackedAssetRemoved(address(trackedAsset), 1, address(0));
        levvaVault.removeTrackedAsset(address(trackedAsset));

        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 0);
        assertEq(levvaVault.trackedAssetsCount(), 0);
    }

    function testRemoveNotLastAsset() public {
        levvaVault.addTrackedAsset(address(trackedAsset));
        MintableERC20 secondTrackedAsset = new MintableERC20("wstUSDTest", "wstUSDTest", 6);
        oracle.setPrice(oracle.ONE(), address(secondTrackedAsset), address(asset));
        levvaVault.addTrackedAsset(address(secondTrackedAsset));

        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 1);
        assertEq(levvaVault.trackedAssetPosition(address(secondTrackedAsset)), 2);

        vm.expectEmit(address(levvaVault));
        emit MultiAssetVaultBase.TrackedAssetRemoved(address(trackedAsset), 1, address(secondTrackedAsset));
        levvaVault.removeTrackedAsset(address(trackedAsset));

        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 0);
        assertEq(levvaVault.trackedAssetPosition(address(secondTrackedAsset)), 1);
        assertEq(levvaVault.trackedAssetsCount(), 1);
    }

    function testRemoveAssetOnlyOwner() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        levvaVault.removeTrackedAsset(address(trackedAsset));
    }

    function testRemoveNotTrackedAsset() public {
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.NotTrackedAsset.selector));
        levvaVault.removeTrackedAsset(address(trackedAsset));
    }

    function testRemoveAssetNotZeroBalance() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        uint256 balance = 1;
        trackedAsset.mint(address(levvaVault), balance);

        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.NotZeroBalance.selector, balance));
        levvaVault.removeTrackedAsset(address(trackedAsset));
    }

    function testSetMinDeposit() public {
        uint256 newMinDeposit = levvaVault.minimalDeposit() + 1;

        vm.expectEmit(address(levvaVault));
        emit MultiAssetVaultBase.MinimalDepositSet(newMinDeposit);
        levvaVault.setMinimalDeposit(newMinDeposit);

        assertEq(levvaVault.minimalDeposit(), newMinDeposit);
    }

    function testSetMinDepositOnlyOwner() public {
        uint256 newMinDeposit = levvaVault.minimalDeposit() + 1;

        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        levvaVault.setMinimalDeposit(newMinDeposit);
    }

    function testSetMinDepositSameValue() public {
        uint256 newMinDeposit = levvaVault.minimalDeposit();

        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setMinimalDeposit(newMinDeposit);
    }

    function testSetMaxTrackedAssets() public {
        uint8 newMaxTrackedAssets = 0;
        vm.expectEmit(address(levvaVault));
        emit MultiAssetVaultBase.MaxTrackedAssetsSet(newMaxTrackedAssets);
        levvaVault.setMaxTrackedAssets(newMaxTrackedAssets);

        assertEq(levvaVault.maxTrackedAssets(), newMaxTrackedAssets);
    }

    function testSetMaxTrackedAssetsOnlyOwner() public {
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        levvaVault.setMaxTrackedAssets(0);
    }

    function testSetMaxTrackedAssetsWrongValue() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.WrongValue.selector));
        levvaVault.setMaxTrackedAssets(0);
    }

    function testSetOracle() public {
        address newOracle = address(new EulerRouterMock());

        vm.expectEmit(address(levvaVault));
        emit OraclePriceProvider.OracleSet(newOracle);
        levvaVault.setOracle(newOracle);

        assertEq(address(levvaVault.oracle()), newOracle);
    }

    function testSetOracleOnlyOwner() public {
        address newOracle = address(new EulerRouterMock());

        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        levvaVault.setOracle(newOracle);
    }

    function testSetOracleSameValue() public {
        address sameOracle = address(levvaVault.oracle());
        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setOracle(sameOracle);
    }

    function testSetOracleZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        levvaVault.setOracle(address(0));
    }

    function testAddVaultManagerZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        levvaVault.addVaultManager(address(0), true);
    }

    function test_renounceOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.Forbidden.selector));
        levvaVaultFactory.renounceOwnership();
    }
}
