// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {IMultiAssetVault} from "../interfaces/IMultiAssetVault.sol";

abstract contract AdapterBase is IERC165, IAdapter {
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
            IMultiAssetVault(msg.sender).trackedAssetPosition(asset) == 0
                && IMultiAssetVault(msg.sender).asset() != asset
        ) {
            revert AdapterBase__InvalidToken(asset);
        }
    }
}
