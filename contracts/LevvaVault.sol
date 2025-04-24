// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MultiAssetVaultBase} from "./base/MultiAssetVaultBase.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract LevvaVault is UUPSUpgradeable, MultiAssetVaultBase, Ownable2StepUpgradeable {
    /// @dev Disabling initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 asset) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __MultiAssetVaultBase_init(asset);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
