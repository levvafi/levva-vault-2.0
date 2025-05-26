// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {IMultiAssetVault} from "../interfaces/IMultiAssetVault.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

abstract contract AdapterBase is Ownable2StepUpgradeable, IERC165, IAdapter {
    error AdapterBase__InvalidToken(address token);

    /// @notice Implementation of ERC165, supports IAdapter and IERC165
    /// @param interfaceId interface identifier
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IAdapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Ensure the asset is vault asset or tracked asset
    /// @param asset asset address
    function _ensureIsValidAsset(address asset) internal view {
        if (
            IMultiAssetVault(address(this)).trackedAssetPosition(asset) == 0
                && IMultiAssetVault(address(this)).asset() != asset
        ) {
            revert AdapterBase__InvalidToken(asset);
        }
    }
}
