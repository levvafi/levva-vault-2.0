// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";

abstract contract MultiAssetVaultBase is ERC4626Upgradeable, Ownable2StepUpgradeable {
    using Asserts for address;
    using Asserts for uint256;

    /// @custom:storage-location erc7201:levva.storage.MultiAssetVaultBase
    struct MultiAssetVaultBaseStorage {
        uint256 minDeposit;
        IERC20[] trackedAssets;
        // if 0, then token is not tracked, otherwise 'trackedAssetsArrayIndex = trackedAssetPosition - 1'
        mapping(address asset => uint256) trackedAssetPosition;
    }

    // keccak256(abi.encode(uint256(keccak256("levva.storage.MultiAssetVaultBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MultiAssetVaultBaseStorageLocation =
        0xb4929dcfd4273b77f5c4c898159c6e34254f398e5914813e7e6f7d3d9f3fbf00;

    function _getMultiAssetVaultBaseStorage() private pure returns (MultiAssetVaultBaseStorage storage $) {
        assembly {
            $.slot := MultiAssetVaultBaseStorageLocation
        }
    }

    error AlreadyTracked(uint256 index);
    error NotTrackedAsset();
    error NotZeroBalance(uint256 balance);
    error LessThanMinDeposit(uint256 minDeposit);

    event NewTrackedAssetAdded(address indexed newTrackedAsset, uint256 indexed position);
    event TrackedAssetRemoved(
        address indexed trackedAssetRemoved, uint256 indexed position, address indexed replacement
    );
    event MinimalDepositSet(uint256 minDeposit);

    function __MultiAssetVaultBase_init(IERC20 asset, string calldata lpName, string calldata lpSymbol)
        internal
        onlyInitializing
    {
        __ERC4626_init(asset);
        __ERC20_init(lpName, lpSymbol);
    }

    function addTrackedAsset(address newTrackedAsset) external onlyOwner {
        newTrackedAsset.assertNotZeroAddress();

        MultiAssetVaultBaseStorage storage $ = _getMultiAssetVaultBaseStorage();

        if ($.trackedAssetPosition[newTrackedAsset] != 0) {
            revert AlreadyTracked($.trackedAssetPosition[newTrackedAsset]);
        }

        $.trackedAssets.push(IERC20(newTrackedAsset));

        uint256 position = $.trackedAssets.length;
        $.trackedAssetPosition[newTrackedAsset] = position;

        emit NewTrackedAssetAdded(newTrackedAsset, position);
    }

    function removeTrackedAsset(address trackedAsset) external onlyOwner {
        MultiAssetVaultBaseStorage storage $ = _getMultiAssetVaultBaseStorage();

        uint256 position = $.trackedAssetPosition[trackedAsset];
        if (position == 0) revert NotTrackedAsset();

        uint256 currentBalance = IERC20(trackedAsset).balanceOf(address(this));
        if (currentBalance != 0) revert NotZeroBalance(currentBalance);

        address replacement;
        uint256 trackedAssetsCount = $.trackedAssets.length;
        if (position != trackedAssetsCount) {
            replacement = address($.trackedAssets[trackedAssetsCount - 1]);
            $.trackedAssets[position - 1] = IERC20(replacement);
            $.trackedAssetPosition[replacement] = position;
        }

        $.trackedAssets.pop();
        delete $.trackedAssetPosition[trackedAsset];

        emit TrackedAssetRemoved(trackedAsset, position, replacement);
    }

    function setMinimalDeposit(uint256 minDeposit) external onlyOwner {
        MultiAssetVaultBaseStorage storage $ = _getMultiAssetVaultBaseStorage();
        minDeposit.assertNotSameValue($.minDeposit);

        $.minDeposit = minDeposit;
        emit MinimalDepositSet(minDeposit);
    }

    /// @inheritdoc ERC4626Upgradeable
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

    function trackedAssetPosition(address trackedAsset) external view returns (uint256) {
        return _getMultiAssetVaultBaseStorage().trackedAssetPosition[trackedAsset];
    }

    function minimalDeposit() external view returns (uint256) {
        return _getMultiAssetVaultBaseStorage().minDeposit;
    }

    // TODO: make virtual later, must be implemented in 'OracleInteractor' or something
    function convert(address, /*fromAsset*/ address, /*toAsset*/ uint256 amount) internal pure returns (uint256) {
        return amount;
    }

    /// @inheritdoc ERC4626Upgradeable
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        uint256 minDeposit = _getMultiAssetVaultBaseStorage().minDeposit;
        if (minDeposit == 0) {
            assets.assertNotZeroAmount();
        } else if (assets < minDeposit) {
            revert LessThanMinDeposit(minDeposit);
        }

        super._deposit(caller, receiver, assets, shares);
    }
}
