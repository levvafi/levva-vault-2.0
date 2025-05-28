// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniversalRewardsDistributorBase} from "./IUniversalRewardsDistributorBase.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IMetaMorphoFactory} from "./IMetaMorphoFactory.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {Asserts} from "../../libraries/Asserts.sol";

abstract contract MorphoAdapterBase is AdapterBase {
    using Asserts for address;
    using SafeERC20 for IERC20;

    IMetaMorphoFactory internal immutable i_metaMorphoFactory;

    error MorphoAdapterBase__InvalidMorphoVault();

    constructor(address metaMorphoFactory) AdapterBase() {
        metaMorphoFactory.assertNotZeroAddress();
        i_metaMorphoFactory = IMetaMorphoFactory(metaMorphoFactory);
    }

    /// @notice Deposits assets into a Morpho vault, receives shares in return
    /// @param morphoVault The address of the Morpho vault to deposit into
    /// @param assets The amount of assets to deposit
    function deposit(address morphoVault, uint256 assets) external returns (uint256 shares) {
        _ensureIsValidMorphoVault(morphoVault);
        _ensureIsValidAsset(morphoVault);

        address asset = IERC4626(morphoVault).asset();
        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, assets);
        IERC20(asset).forceApprove(morphoVault, assets);

        shares = IERC4626(morphoVault).deposit(assets, msg.sender);
    }

    /// @notice Withdraws assets from a Morpho vault, burns shares in return
    /// @param morphoVault The address of the Morpho vault to withdraw from
    /// @param shares The amount of shares to burn
    function redeem(address morphoVault, uint256 shares) external returns (uint256 assets) {
        _ensureIsValidMorphoVault(morphoVault);
        address asset = IERC4626(morphoVault).asset();
        _ensureIsValidAsset(asset);

        IAdapterCallback(msg.sender).adapterCallback(address(this), morphoVault, shares);
        assets = IERC4626(morphoVault).redeem(shares, msg.sender, address(this));
    }

    /// @notice Claims rewards from a UniversalRewardsDistributor contract. Call data must be received from morpho api
    /// @param rewardsDistributor The address of the UniversalRewardsDistributor contract
    /// @param reward The address of the reward token to claim
    /// @param claimable The amount of claimable rewards
    /// @param proof The merkle proof to verify the claim
    function claimRewards(address rewardsDistributor, address reward, uint256 claimable, bytes32[] calldata proof)
        external
    {
        _ensureIsValidAsset(reward);
        IUniversalRewardsDistributorBase(rewardsDistributor).claim(msg.sender, reward, claimable, proof);
    }

    function getMetaMorphoFactory() external view returns (address) {
        return address(i_metaMorphoFactory);
    }

    function _ensureIsValidMorphoVault(address morphoVault) internal view {
        if (!i_metaMorphoFactory.isMetaMorpho(morphoVault)) {
            revert MorphoAdapterBase__InvalidMorphoVault();
        }
    }
}
