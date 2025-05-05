// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";
import {FeeCollector} from "./FeeCollector.sol";

abstract contract MultiAssetVaultBase is ERC4626Upgradeable, Ownable2StepUpgradeable, FeeCollector {
    using Asserts for address;
    using Asserts for uint256;
    using Math for uint256;

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

    function __MultiAssetVaultBase_init(
        IERC20 asset,
        string calldata lpName,
        string calldata lpSymbol,
        address feeCollector
    ) internal onlyInitializing {
        __ERC4626_init(asset);
        __ERC20_init(lpName, lpSymbol);
        __FeeCollector_init(feeCollector);
    }

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();

        _collectFees(_totalAssets, _totalSupply);

        uint256 shares = _convertToShares(assets, _totalAssets, _totalSupply, Math.Rounding.Floor);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 shares, address receiver) public override returns (uint256) {
        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();

        _collectFees(_totalAssets, _totalSupply);

        uint256 assets = _convertToAssets(shares, _totalAssets, _totalSupply, Math.Rounding.Ceil);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        // uint256 maxAssets = maxWithdraw(owner);
        // if (assets > maxAssets) {
        //     revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        // }

        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();

        _collectFees(_totalAssets, _totalSupply);

        uint256 shares = _convertToShares(assets, _totalAssets, _totalSupply, Math.Rounding.Ceil);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        // uint256 maxShares = maxRedeem(owner);
        // if (shares > maxShares) {
        //     revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        // }

        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();

        _collectFees(_totalAssets, _totalSupply);

        uint256 assets = _convertToAssets(shares, _totalAssets, _totalSupply, Math.Rounding.Floor);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
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

    function setFeeCollector(address newFeeCollector) external onlyOwner {
       _setFeeCollector(newFeeCollector);
    }

    function setManagementFeeIR(uint48 newManagementFeeIR) external onlyOwner {
        _setManagementFeeIR(newManagementFeeIR);
    }

    function setPerformanceFeeRatio(uint48 newPerformanceFeeRatio) external onlyOwner {
        _setPerformanceFeeRatio(newPerformanceFeeRatio);
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

    function _convertToShares(uint256 assets, uint256 _totalAssets, uint256 _totalSupply, Math.Rounding rounding)
        private
        view
        returns (uint256)
    {
        return assets.mulDiv(_totalSupply + 10 ** _decimalsOffset(), _totalAssets + 1, rounding);
    }

    function _convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _totalSupply, Math.Rounding rounding)
        private
        view
        returns (uint256)
    {
        return shares.mulDiv(_totalAssets + 1, _totalSupply + 10 ** _decimalsOffset(), rounding);
    }
}
