// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";

abstract contract VaultAccessControl is Initializable, Ownable2StepUpgradeable {
    using Asserts for address;

    /// @dev 'VaultAccessControlStorage' storage slot address
    /// @dev keccak256(abi.encode(uint256(keccak256("levva-vault.VaultAccessControlStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultAccessControlStorageLocation =
        0x02eb9da8ea38b41b4650ef2b85e08be861a787c9657df49bae75bf68e905cf00;

    struct VaultAccessControlStorage {
        address withdrawalQueue;
        /// @dev vault managers
        mapping(address => bool) _vaultManagers;
    }

    /// @dev returns storage slot of 'VaultAccessControlStorage' struct
    function _getVaultAccessControlStorage() private pure returns (VaultAccessControlStorage storage $) {
        assembly {
            $.slot := VaultAccessControlStorageLocation
        }
    }

    error NoAccess(address sender);
    error QueueAlreadySet(address queue);

    modifier onlyVaultManager() {
        _onlyVaultManager();
        _;
    }

    modifier onlyQueue() {
        _onlyQueue();
        _;
    }

    function __VaultAccessControl_init(address owner) internal onlyInitializing {
        __Ownable_init(owner);
    }

    function addVaultManager(address user, bool add) external onlyOwner {
        _getVaultAccessControlStorage()._vaultManagers[user] = add;
    }

    function setWithdrawalQueue(address queue) external onlyOwner {
        queue.assertNotZeroAddress();

        VaultAccessControlStorage storage $ = _getVaultAccessControlStorage();
        if ($.withdrawalQueue != address(0)) revert QueueAlreadySet($.withdrawalQueue);
        $.withdrawalQueue = queue;
    }

    function withdrawalQueue() external view returns (address) {
        return _getWithdrawalQueue();
    }

    function _getWithdrawalQueue() internal view returns (address) {
        return _getVaultAccessControlStorage().withdrawalQueue;
    }

    function _onlyVaultManager() private view {
        if (!_getVaultAccessControlStorage()._vaultManagers[msg.sender]) revert NoAccess(msg.sender);
    }

    function _onlyQueue() private view {
        if (msg.sender != _getWithdrawalQueue()) revert NoAccess(msg.sender);
    }
}
