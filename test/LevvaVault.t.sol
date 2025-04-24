// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {LevvaVault} from "../contracts/LevvaVault.sol";
import {MintableERC20} from "./MintableERC20.t.sol";

contract LevvaVaultTest is Test {
    LevvaVault public levvaVaultImplementation;
    ERC1967Proxy public levvaVaultProxy;
    LevvaVault public levvaVault;

    MintableERC20 public asset;

    function setUp() public {
        asset = new MintableERC20("USDTest", "USDTest", 6);

        levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(LevvaVault.initialize.selector, IERC20(asset));
        levvaVaultProxy = new ERC1967Proxy(address(levvaVaultImplementation), data);
        levvaVault = LevvaVault(address(levvaVaultProxy));
    }

    function testInitialize() public view {
        assertEq(address(levvaVault.asset()), address(asset));
        assertEq(levvaVault.owner(), address(this));
    }

    function testTotalAssets() public {
        uint256 depositAmount = 10 ** 12;
        asset.mint(address(this), depositAmount);
        asset.approve(address(levvaVault), depositAmount);
        levvaVault.deposit(depositAmount, address(this));

        assertEq(levvaVault.totalAssets(), depositAmount);
    }
}
