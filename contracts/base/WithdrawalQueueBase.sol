// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";

abstract contract WithdrawalQueueBase is Initializable, Ownable2StepUpgradeable {
    using Asserts for address;

    /// @custom:storage-location erc7201:levva.storage.WithdrawalQueueBaseStorage
    struct WithdrawalQueueBaseStorage {
        uint256 lastRequestId;
        uint256 lastFinalizedRequestId;
        IERC4626 levvaVault;
        mapping(address => bool) finalizers;
        mapping(uint256 requestId => WithdrawalRequest item) items;
    }

    /// @dev 'WithdrawalQueueStorageData' storage slot address
    /// @dev keccak256(abi.encode(uint256(keccak256("levva-vault.WithdrawalQueueBaseStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalQueueBaseStorageLocation =
        0x78f0351b059b6aed2e654ce4a38d42d975f3dcea3167a2d4518f5ef39639c600;

    function _getWithdrawalQueueBaseStorage() private pure returns (WithdrawalQueueBaseStorage storage $) {
        assembly {
            $.slot := WithdrawalQueueBaseStorageLocation
        }
    }

    struct WithdrawalRequest {
        uint256 shares;
        uint256 assets;
    }

    event FinalizerSet(address indexed finalizer, bool added);

    error NoAccess(address sender);
    error FutureFinalization();
    error AlreadyFinalized();

    modifier onlyLevvaVault() {
        _onlyLevvaVault();
        _;
    }

    modifier onlyFinalizer() {
        _onlyFinalizer();
        _;
    }

    function __WithdrawalQueueBase_init(address owner, address _levvaVault) internal onlyInitializing {
        __Ownable_init(owner);

        _levvaVault.assertNotZeroAddress();
        _getWithdrawalQueueBaseStorage().levvaVault = IERC4626(_levvaVault);
    }

    function addFinalizer(address finalizer, bool add) external onlyOwner {
        _getWithdrawalQueueBaseStorage().finalizers[finalizer] = add;
        emit FinalizerSet(finalizer, add);
    }

    function getWithdrawalRequest(uint256 requestId) external view returns (WithdrawalRequest memory) {
        return _getWithdrawalRequest(requestId);
    }

    function levvaVault() external view returns (IERC4626) {
        return _getLevvaVault();
    }

    function isFinalizer(address finalizer) external view returns (bool) {
        return _getWithdrawalQueueBaseStorage().finalizers[finalizer];
    }

    function _enqueueRequest(uint256 shares, uint256 assets) internal returns (uint256 requestId) {
        WithdrawalQueueBaseStorage storage queue = _getWithdrawalQueueBaseStorage();
        unchecked {
            requestId = ++queue.lastRequestId;
        }
        queue.items[requestId] = WithdrawalRequest(shares, assets);
    }

    function _removeRequest(uint256 requestId) internal returns (WithdrawalRequest memory request) {
        WithdrawalQueueBaseStorage storage queue = _getWithdrawalQueueBaseStorage();
        request = queue.items[requestId];
        delete queue.items[requestId];
    }

    function _finalizeRequests(uint256 newLastFinalizedRequestId) internal {
        WithdrawalQueueBaseStorage storage queue = _getWithdrawalQueueBaseStorage();
        if (queue.lastFinalizedRequestId >= newLastFinalizedRequestId) revert AlreadyFinalized();
        if (queue.lastRequestId < newLastFinalizedRequestId) revert FutureFinalization();

        queue.lastFinalizedRequestId = newLastFinalizedRequestId;
    }

    function _getWithdrawalRequest(uint256 requestId) internal view returns (WithdrawalRequest storage) {
        WithdrawalQueueBaseStorage storage queue = _getWithdrawalQueueBaseStorage();
        return queue.items[requestId];
    }

    function _getLevvaVault() internal view returns (IERC4626) {
        return _getWithdrawalQueueBaseStorage().levvaVault;
    }

    function _onlyLevvaVault() private view {
        if (msg.sender != address(_getLevvaVault())) revert NoAccess(msg.sender);
    }

    function _onlyFinalizer() private view {
        if (!_getWithdrawalQueueBaseStorage().finalizers[msg.sender]) revert NoAccess(msg.sender);
    }
}
