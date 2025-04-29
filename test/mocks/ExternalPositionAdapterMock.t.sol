// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";

contract ExternalPositionAdapterMock is IERC165, IAdapter, IExternalPositionAdapter {
    address private immutable _managedAsset;
    address private immutable _debtAsset;
    bytes4 private _adapterId = bytes4(keccak256("ExternalPositionAdapterMock"));

    uint256 public actionsExecuted = 0;
    bytes public recentCalldata;

    constructor(address managedAsset, address debtAsset) {
        _managedAsset = managedAsset;
        _debtAsset = debtAsset;
    }

    function testAction(bytes calldata data) external returns (uint256) {
        actionsExecuted += 1;
        recentCalldata = data;
        return actionsExecuted;
    }

    function setAdapterId(bytes4 newId) external {
        _adapterId = newId;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAdapter).interfaceId || interfaceId == type(IExternalPositionAdapter).interfaceId;
    }

    function getAdapterId() external view override returns (bytes4) {
        return _adapterId;
    }

    function getManagedAssets() external view override returns (address[] memory assets, uint256[] memory amounts) {
        assets = new address[](1);
        assets[0] = _managedAsset;

        amounts = new uint256[](1);
        amounts[0] = 10_000_000;
    }

    function getDebtAssets() external view override returns (address[] memory assets, uint256[] memory amounts) {
        assets = new address[](1);
        assets[0] = _debtAsset;

        amounts = new uint256[](1);
        amounts[0] = 1_000_000;
    }
}
