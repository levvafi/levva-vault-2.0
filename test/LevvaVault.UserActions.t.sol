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

contract LevvaVaultUserActionsTest is Test {
    LevvaVault public levvaVaultImplementation = new LevvaVault();
    ERC1967Proxy public levvaVaultProxy;
    LevvaVault public levvaVault;

    MintableERC20 public asset = new MintableERC20("USDTest", "USDTest", 6);
    MintableERC20 public trackedAsset = new MintableERC20("wstUSDTest", "wstUSDTest", 18);

    string lpName = "lpName";
    string lpSymbol = "lpSymbol";

    address nonOwner = address(0xDEAD);
    address user = address(0x987654321);
    uint256 minDeposit = 1_000_000;

    function setUp() public {
        bytes memory data = abi.encodeWithSelector(LevvaVault.initialize.selector, IERC20(asset), lpName, lpSymbol);
        levvaVaultProxy = new ERC1967Proxy(address(levvaVaultImplementation), data);
        levvaVault = LevvaVault(address(levvaVaultProxy));

        levvaVault.setMinimalDeposit(minDeposit);
        asset.mint(user, 10 * minDeposit);
    }

    function testDeposit() public {
        vm.prank(user);
        asset.approve(address(levvaVault), minDeposit);

        vm.prank(user);
        levvaVault.deposit(minDeposit, user);
    }

    function testLessThanMinDeposit() public {
        vm.prank(user);
        asset.approve(address(levvaVault), minDeposit - 1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.LessThanMinDeposit.selector, minDeposit));
        levvaVault.deposit(minDeposit - 1, user);
    }

    function testZeroAmount() public {
        levvaVault.setMinimalDeposit(0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAmount.selector));
        levvaVault.deposit(0, user);
    }

    function testMint() public {
        vm.prank(user);
        asset.approve(address(levvaVault), minDeposit);

        vm.prank(user);
        levvaVault.mint(minDeposit, user);
    }

    function testLessThanMinDepositMint() public {
        vm.prank(user);
        asset.approve(address(levvaVault), minDeposit - 1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MultiAssetVaultBase.LessThanMinDeposit.selector, minDeposit));
        levvaVault.mint(minDeposit - 1, user);
    }

    function testZeroAmountMint() public {
        levvaVault.setMinimalDeposit(0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAmount.selector));
        levvaVault.mint(0, user);
    }
}
