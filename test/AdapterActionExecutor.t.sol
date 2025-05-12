// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {AdapterActionExecutor} from "../contracts/base/AdapterActionExecutor.sol";
import {AdapterMock} from "./mocks/AdapterMock.t.sol";
import {ExternalPositionAdapterMock} from "./mocks/ExternalPositionAdapterMock.t.sol";

contract AdapterActionExecutorTest is TestSetUp {
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
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
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
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        vm.prank(NO_ACCESS);
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
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.action.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        bytes memory externalPositionAdapterCalldata = "externalPositionAdapterData";
        bytes memory externalPositionAdapterCalldataWithSelector =
            abi.encodeWithSelector(externalPositionAdapter.action.selector, externalPositionAdapterCalldata);
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

        vm.prank(VAULT_MANAGER);
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
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.action.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        bytes memory externalPositionAdapterCalldata = "externalPositionAdapterData";
        bytes memory externalPositionAdapterCalldataWithSelector =
            abi.encodeWithSelector(externalPositionAdapter.action.selector, externalPositionAdapterCalldata);
        args[1] = AdapterActionExecutor.AdapterActionArg({
            adapterId: externalPositionAdapter.getAdapterId(),
            data: externalPositionAdapterCalldataWithSelector
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, NO_ACCESS, levvaVault.VAULT_MANAGER_ROLE()
            )
        );
        vm.prank(NO_ACCESS);
        levvaVault.executeAdapterAction(args);
    }

    function testExecuteAdapterActionUnknownAdapter() public {
        AdapterActionExecutor.AdapterActionArg[] memory args = new AdapterActionExecutor.AdapterActionArg[](1);

        bytes memory adapterCalldata = "adapterData";
        bytes memory adapterCalldataWithSelector = abi.encodeWithSelector(adapter.action.selector, adapterCalldata);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: adapter.getAdapterId(),
            data: adapterCalldataWithSelector
        });

        vm.expectRevert(abi.encodeWithSelector(AdapterActionExecutor.UnknownAdapter.selector, adapter.getAdapterId()));
        vm.prank(VAULT_MANAGER);
        levvaVault.executeAdapterAction(args);
    }
}
