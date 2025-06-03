// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {LevvaVault} from "../LevvaVault.sol";
import {WithdrawalQueue} from "../WithdrawalQueue.sol";

abstract contract FactoryBase is Initializable, Ownable2StepUpgradeable {
    /// @custom:storage-location erc7201:levva.storage.FactoryBase
    struct FactoryBaseStorage {
        mapping(address => bool) isLevvaVault;
        UpgradeableBeacon vaultBeacon;
        UpgradeableBeacon withdrawalQueueBeacon;
    }

    // keccak256(abi.encode(uint256(keccak256("levva.storage.FactoryBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FactoryBaseStorageLocation =
        0xcc8f7fa260fdbb6100fec3c743c29c0691eb5ad58bd519936bac66b66bacb700;

    function _getFactoryBaseStorage() private pure returns (FactoryBaseStorage storage $) {
        assembly {
            $.slot := FactoryBaseStorageLocation
        }
    }

    event NewVaultDeployed(
        address indexed vault, address indexed withdrawalQueue, string indexed lpName, address asset
    );

    function __FactoryBase_init(address owner, address vaultImplementation, address withdrawalQueueImplementation)
        internal
        onlyInitializing
    {
        __Ownable_init(owner);

        FactoryBaseStorage storage $ = _getFactoryBaseStorage();
        $.vaultBeacon = new UpgradeableBeacon(vaultImplementation, owner);
        $.withdrawalQueueBeacon = new UpgradeableBeacon(withdrawalQueueImplementation, owner);
    }

    function vaultBeacon() public view returns (address) {
        return address(_getFactoryBaseStorage().vaultBeacon);
    }

    function withdrawalQueueBeacon() public view returns (address) {
        return address(_getFactoryBaseStorage().withdrawalQueueBeacon);
    }

    function isLevvaVault(address levvaVault) external view returns (bool) {
        return _getFactoryBaseStorage().isLevvaVault[levvaVault];
    }

    function _deployVault(
        address asset,
        string calldata lpName,
        string calldata lpSymbol,
        address feeCollector,
        address eulerOracle
    ) internal returns (address vault, address queue) {
        vault = address(new BeaconProxy(vaultBeacon(), ""));

        bytes memory queueInitializeCalldata =
            abi.encodeWithSelector(WithdrawalQueue.initialize.selector, msg.sender, vault);
        queue = address(new BeaconProxy(withdrawalQueueBeacon(), queueInitializeCalldata));

        LevvaVault(vault).initialize(msg.sender, asset, lpName, lpSymbol, feeCollector, eulerOracle, queue);

        _getFactoryBaseStorage().isLevvaVault[vault] = true;

        emit NewVaultDeployed(vault, queue, lpName, asset);
    }
}
