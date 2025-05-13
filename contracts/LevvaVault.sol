// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MultiAssetVaultBase} from "./base/MultiAssetVaultBase.sol";
import {AdapterActionExecutor} from "./base/AdapterActionExecutor.sol";
import {OraclePriceProvider} from "./base/OraclePriceProvider.sol";
import {IEulerPriceOracle} from "./interfaces/IEulerPriceOracle.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract LevvaVault is UUPSUpgradeable, MultiAssetVaultBase, AdapterActionExecutor, OraclePriceProvider {
    /// @dev Disabling initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20 asset,
        string calldata lpName,
        string calldata lpSymbol,
        address feeCollector,
        address eulerOracle
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __MultiAssetVaultBase_init(asset, lpName, lpSymbol, feeCollector);
        __OraclePriceProvider_init(eulerOracle);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function oracle() public view override(MultiAssetVaultBase, OraclePriceProvider) returns (IEulerPriceOracle) {
        return OraclePriceProvider.oracle();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
