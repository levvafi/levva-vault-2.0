// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {LevvaVault} from "../contracts/LevvaVault.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {MultiAssetVaultBase} from "../contracts/base/MultiAssetVaultBase.sol";
import {MintableERC20} from "./mocks/MintableERC20.t.sol";
import {EulerRouterMock} from "./mocks/EulerRouterMock.t.sol";

contract LevvaVaultTest is Test {
    LevvaVault public levvaVaultImplementation;
    ERC1967Proxy public levvaVaultProxy;
    LevvaVault public levvaVault;

    MintableERC20 public asset = new MintableERC20("USDTest", "USDTest", 6);
    MintableERC20 public trackedAsset = new MintableERC20("wstUSDTest", "wstUSDTest", 18);

    EulerRouterMock oracle = new EulerRouterMock();

    string lpName = "lpName";
    string lpSymbol = "lpSymbol";

    address nonOwner = address(0xDEAD);
    address feeCollector = address(0xFEE);

    function setUp() public {
        levvaVaultImplementation = new LevvaVault();
        bytes memory data =
            abi.encodeWithSelector(LevvaVault.initialize.selector, IERC20(asset), lpName, lpSymbol, feeCollector, address(oracle));
        levvaVaultProxy = new ERC1967Proxy(address(levvaVaultImplementation), data);
        levvaVault = LevvaVault(address(levvaVaultProxy));
    }

    function testInitialize() public view {
        assertEq(address(levvaVault.asset()), address(asset));
        assertEq(levvaVault.owner(), address(this));
        assertEq(levvaVault.name(), lpName);
        assertEq(levvaVault.symbol(), lpSymbol);
        assertEq(levvaVault.getFeeCollectorStorage().feeCollector, feeCollector);
        assertEq(levvaVault.getFeeCollectorStorage().highWaterMarkPerShare, 10 ** levvaVault.decimals());
    }

    function testAddNewAsset() public {
        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 0);

        vm.expectEmit(address(levvaVault));
        emit MultiAssetVaultBase.NewTrackedAssetAdded(address(trackedAsset), 1);
        levvaVault.addTrackedAsset(address(trackedAsset));

        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 1);
    }

    function testAddNewAssetOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
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

    function testAddNewAssetZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        levvaVault.addTrackedAsset(address(0));
    }

    function testRemoveLastAsset() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        vm.expectEmit(address(levvaVault));
        emit MultiAssetVaultBase.TrackedAssetRemoved(address(trackedAsset), 1, address(0));
        levvaVault.removeTrackedAsset(address(trackedAsset));

        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 0);
    }

    function testRemoveNotLastAsset() public {
        levvaVault.addTrackedAsset(address(trackedAsset));
        MintableERC20 secondTrackedAsset = new MintableERC20("wstUSDTest2", "wstUSDTest2", 18);
        levvaVault.addTrackedAsset(address(secondTrackedAsset));

        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 1);
        assertEq(levvaVault.trackedAssetPosition(address(secondTrackedAsset)), 2);

        vm.expectEmit(address(levvaVault));
        emit MultiAssetVaultBase.TrackedAssetRemoved(address(trackedAsset), 1, address(secondTrackedAsset));
        levvaVault.removeTrackedAsset(address(trackedAsset));

        assertEq(levvaVault.trackedAssetPosition(address(trackedAsset)), 0);
        assertEq(levvaVault.trackedAssetPosition(address(secondTrackedAsset)), 1);
    }

    function testRemoveAssetOnlyOwner() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
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

    function testTotalAssets() public {
        levvaVault.addTrackedAsset(address(trackedAsset));

        uint256 depositAmount = 10 ** 12;
        asset.mint(address(this), depositAmount);
        asset.approve(address(levvaVault), depositAmount);
        levvaVault.deposit(depositAmount, address(this));

        assertEq(levvaVault.totalAssets(), depositAmount);

        uint256 trackedAssetAmount = 1_000 * 10 ** 18;
        trackedAsset.mint(address(levvaVault), trackedAssetAmount);

        uint256 expectedTotalAssets = trackedAssetAmount + depositAmount;
        assertEq(levvaVault.totalAssets(), expectedTotalAssets);
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

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        levvaVault.setMinimalDeposit(newMinDeposit);
    }

    function testSetMinDepositSameValue() public {
        uint256 newMinDeposit = levvaVault.minimalDeposit();

        vm.expectRevert(abi.encodeWithSelector(Asserts.SameValue.selector));
        levvaVault.setMinimalDeposit(newMinDeposit);
    }
}
