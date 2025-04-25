// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MultiAssetVaultBase} from "./base/MultiAssetVaultBase.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract LevvaVault is UUPSUpgradeable, MultiAssetVaultBase {
    /// @dev Disabling initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 asset, string calldata lpName, string calldata lpSymbol) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __MultiAssetVaultBase_init(asset, lpName, lpSymbol);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
