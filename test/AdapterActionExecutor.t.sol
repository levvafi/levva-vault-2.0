// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {LevvaVault} from "../contracts/LevvaVault.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {MintableERC20} from "./mocks/MintableERC20.t.sol";
import {AdapterMock} from "./mocks/AdapterMock.t.sol";
import {ExternalPositionAdapterMock} from "./mocks/ExternalPositionAdapterMock.t.sol";

contract AdapterActionExecutorTest is Test {
    LevvaVault public levvaVaultImplementation;
    ERC1967Proxy public levvaVaultProxy;
    LevvaVault public levvaVault;

    MintableERC20 public asset = new MintableERC20("USDTest", "USDTest", 6);
    MintableERC20 public externalPositionManagedAsset = new MintableERC20("EPMA", "EPMA", 18);
    MintableERC20 public externalPositionDebtAsset = new MintableERC20("EPDA", "EPDA", 18);

    AdapterMock adapter = new AdapterMock();
    ExternalPositionAdapterMock externalPositionAdapter =
        new ExternalPositionAdapterMock(address(externalPositionManagedAsset), address(externalPositionDebtAsset));

    string lpName = "lpName";
    string lpSymbol = "lpSymbol";

    address noAccess = address(0xDEAD);
    address vaultManager = address(0x123456789);
    address feeCollector = address(0xFEE);

    function setUp() public {
        levvaVaultImplementation = new LevvaVault();
        bytes memory data =
            abi.encodeWithSelector(LevvaVault.initialize.selector, IERC20(asset), lpName, lpSymbol, feeCollector);
        levvaVaultProxy = new ERC1967Proxy(address(levvaVaultImplementation), data);
        levvaVault = LevvaVault(address(levvaVaultProxy));

        levvaVault.grantRole(levvaVault.VAULT_MANAGER_ROLE(), vaultManager);
    }

    function testAddAdapter() public {
        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.NewAdapterAdded(adapter.getAdapterId(), address(adapter));

        levvaVault.addAdapter(address(adapter));
        assertEq(address(levvaVault.getAdapter(adapter.getAdapterId())), address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);
    }

    function testAddExternalPositionAdapter() public {
        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.NewAdapterAdded(
            externalPositionAdapter.getAdapterId(), address(externalPositionAdapter)
        );

        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.NewExternalPositionAdapterAdded(address(externalPositionAdapter), 1);

        levvaVault.addAdapter(address(externalPositionAdapter));

        assertEq(
            address(levvaVault.getAdapter(externalPositionAdapter.getAdapterId())), address(externalPositionAdapter)
        );
        assertEq(levvaVault.externalPositionAdapterPosition(address(externalPositionAdapter)), 1);
    }

    function testAddAdapterOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, noAccess));
        vm.prank(noAccess);
        levvaVault.addAdapter(address(adapter));
    }

    function testAddAdapterAlreadyExists() public {
        levvaVault.addAdapter(address(adapter));

        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.AdapterAlreadyExists.selector, address(adapter)));
        levvaVault.addAdapter(address(adapter));
    }

    function testAddAdapterWrongAddress() public {
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.WrongAddress.selector));
        levvaVault.addAdapter(address(asset));
    }

    function testRemoveAdapter() public {
        levvaVault.addAdapter(address(adapter));

        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.AdapterRemoved(adapter.getAdapterId());

        levvaVault.removeAdapter(address(adapter));
        assertEq(address(levvaVault.getAdapter(adapter.getAdapterId())), address(0));
    }

    function testRemoveExternalPositionAdapterLast() public {
        levvaVault.addAdapter(address(externalPositionAdapter));

        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.AdapterRemoved(externalPositionAdapter.getAdapterId());

        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.ExternalPositionAdapterRemoved(address(externalPositionAdapter), 1, address(0));

        levvaVault.removeAdapter(address(externalPositionAdapter));

        assertEq(address(levvaVault.getAdapter(adapter.getAdapterId())), address(0));
        assertEq(levvaVault.externalPositionAdapterPosition(address(externalPositionAdapter)), 0);
    }

    function testRemoveExternalPositionAdapterNotLast() public {
        ExternalPositionAdapterMock secondExternalPositionAdapter =
            new ExternalPositionAdapterMock(address(externalPositionManagedAsset), address(externalPositionDebtAsset));
        secondExternalPositionAdapter.setAdapterId(bytes4(keccak256("SecondExternalPositionAdapterMock")));

        levvaVault.addAdapter(address(externalPositionAdapter));
        levvaVault.addAdapter(address(secondExternalPositionAdapter));

        assertEq(levvaVault.externalPositionAdapterPosition(address(externalPositionAdapter)), 1);
        assertEq(levvaVault.externalPositionAdapterPosition(address(secondExternalPositionAdapter)), 2);

        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.AdapterRemoved(externalPositionAdapter.getAdapterId());

        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.ExternalPositionAdapterRemoved(
            address(externalPositionAdapter), 1, address(secondExternalPositionAdapter)
        );

        levvaVault.removeAdapter(address(externalPositionAdapter));

        assertEq(address(levvaVault.getAdapter(adapter.getAdapterId())), address(0));
        assertEq(levvaVault.externalPositionAdapterPosition(address(externalPositionAdapter)), 0);
        assertEq(levvaVault.externalPositionAdapterPosition(address(secondExternalPositionAdapter)), 1);
    }

    function testRemoveAdapterOnlyOwner() public {
        levvaVault.addAdapter(address(adapter));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, noAccess));
        vm.prank(noAccess);
        levvaVault.removeAdapter(address(adapter));
    }

    function testRemoveAdapterUnknownAdapter() public {
        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.UnknownAdapter.selector, adapter.getAdapterId()));
        levvaVault.removeAdapter(address(adapter));
    }

    function testExecuteAdapterAction() public {
        levvaVault.addAdapter(address(adapter));
        levvaVault.addAdapter(address(externalPositionAdapter));

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](2);

        bytes memory adapterCalldata = "adapterData";
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.testAction.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        bytes memory externalPositionAdapterCalldata = "externalPositionAdapterData";
        bytes memory externalPositionAdapterCalldataWithSelector =
            abi.encodeWithSelector(externalPositionAdapter.testAction.selector, externalPositionAdapterCalldata);
        args[1] = AdapterActionExecutor.AdapterActionArg({
            adapterId: externalPositionAdapter.getAdapterId(),
            data: externalPositionAdapterCalldataWithSelector
        });

        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.AdapterActionExecuted(
            adapter.getAdapterId(), adapterCalldataWithSelector, abi.encode(uint256(1))
        );

        vm.expectEmit(address(levvaVault));
        emit AdapterActionExecutor.AdapterActionExecuted(
            externalPositionAdapter.getAdapterId(), externalPositionAdapterCalldataWithSelector, abi.encode(uint256(1))
        );

        vm.prank(vaultManager);
        levvaVault.executeAdapterAction(args);

        assertEq(adapter.actionsExecuted(), 1);
        assertEq(adapter.recentCalldata(), adapterCalldata);

        assertEq(externalPositionAdapter.actionsExecuted(), 1);
        assertEq(externalPositionAdapter.recentCalldata(), externalPositionAdapterCalldata);
    }

    function testExecuteAdapterActionOnlyRole() public {
        levvaVault.addAdapter(address(adapter));
        levvaVault.addAdapter(address(externalPositionAdapter));

        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](2);

        bytes memory adapterCalldata = "adapterData";
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.testAction.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        bytes memory externalPositionAdapterCalldata = "externalPositionAdapterData";
        bytes memory externalPositionAdapterCalldataWithSelector =
            abi.encodeWithSelector(externalPositionAdapter.testAction.selector, externalPositionAdapterCalldata);
        args[1] = AdapterActionExecutor.AdapterActionArg({
            adapterId: externalPositionAdapter.getAdapterId(),
            data: externalPositionAdapterCalldataWithSelector
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, noAccess, levvaVault.VAULT_MANAGER_ROLE()
            )
        );
        vm.prank(noAccess);
        levvaVault.executeAdapterAction(args);
    }

    function testExecuteAdapterActionUnknownAdapter() public {
        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](1);

        bytes memory adapterCalldata = "adapterData";
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.testAction.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.UnknownAdapter.selector, adapter.getAdapterId()));
        vm.prank(vaultManager);
        levvaVault.executeAdapterAction(args);
    }
}
