// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MultiAssetVaultBase} from "./base/MultiAssetVaultBase.sol";
import {IEulerPriceOracle} from "./interfaces/IEulerPriceOracle.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract LevvaVault is MultiAssetVaultBase {
    /// @dev Disabling initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner,
        address asset,
        string calldata lpName,
        string calldata lpSymbol,
        address feeCollector,
        address eulerOracle,
        address withdrawalQueue
    ) external initializer {
        __VaultAccessControl_init(owner, withdrawalQueue);
        __MultiAssetVaultBase_init(IERC20(asset), lpName, lpSymbol, feeCollector);
        __OraclePriceProvider_init(eulerOracle);
    }
}
