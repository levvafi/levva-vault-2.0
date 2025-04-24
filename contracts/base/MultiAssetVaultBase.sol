// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

abstract contract MultiAssetVaultBase is ERC4626Upgradeable {
    /// @custom:storage-location erc7201:levva.storage.MultiAssetVaultBase
    struct MultiAssetVaultBaseStorage {
        IERC20[] trackedAssets;
    }

    // keccak256(abi.encode(uint256(keccak256("levva.storage.MultiAssetVaultBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MultiAssetVaultBaseStorageLocation =
        0xb4929dcfd4273b77f5c4c898159c6e34254f398e5914813e7e6f7d3d9f3fbf00;

    function _getMultiAssetVaultBaseStorage() private pure returns (MultiAssetVaultBaseStorage storage $) {
        assembly {
            $.slot := MultiAssetVaultBaseStorageLocation
        }
    }

    function __MultiAssetVaultBase_init(IERC20 asset) internal onlyInitializing {
        __ERC4626_init(asset);
    }

    function totalAssets() public view override returns (uint256) {
        unchecked {
            address asset = asset();
            uint256 balance = IERC20(asset).balanceOf(address(this));

            IERC20[] storage trackedAssets = _getMultiAssetVaultBaseStorage().trackedAssets;
            uint256 length = trackedAssets.length;

            for (uint256 i; i < length; ++i) {
                IERC20 trackedAsset = trackedAssets[i];
                balance += convert(address(trackedAsset), asset, trackedAsset.balanceOf(address(this)));
            }

            // TODO: take lending protocols into account

            return balance;
        }
    }

    // TODO: make virtual later, must be implemented in 'OracleInteractor' or something
    function convert(address /*fromAsset*/, address /*toAsset*/, uint256 amount) internal pure returns (uint256) {
        return amount;
    }
}