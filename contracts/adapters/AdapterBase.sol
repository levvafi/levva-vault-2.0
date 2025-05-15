// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {IMultiAssetVault} from "../interfaces/IMultiAssetVault.sol";

abstract contract AdapterBase is IERC165, IAdapter {
    error AdapterBase__InvalidToken(address token);

    /// @notice Implementation of ERC165, supports IAdapter and IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAdapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Ensure the asset is vault asset or tracked asset
    function _ensureIsValidAsset(address asset) internal view {
        if (
            IMultiAssetVault(msg.sender).asset() != asset
                && IMultiAssetVault(msg.sender).trackedAssetPosition(asset) == 0
        ) {
            revert AdapterBase__InvalidToken(asset);
        }
    }
}
