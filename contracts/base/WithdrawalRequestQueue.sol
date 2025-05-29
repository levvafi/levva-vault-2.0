// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

abstract contract WithdrawalRequestQueue {
    /// @dev 'WithdrawalQueueStorageData' storage slot address
    /// @dev keccak256(abi.encode(uint256(keccak256("levva-vault.WithdrawalQueueStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalQueueStorageLocation =
        0x4ff390a5d5a11ce79e4a39c0047f1e548cef89b95e951e10719d61464ab9a900;

    struct WithdrawalRequest {
        uint256 shares;
        uint256 assets;
    }

    struct WithdrawalQueueStorage {
        uint256 lastRequestId;
        uint256 lastFinalizedRequestId;
        mapping(uint256 requestId => WithdrawalRequest item) items;
    }

    function _getWithdrawalQueueStorageData() private pure returns (WithdrawalQueueStorage storage $) {
        assembly {
            $.slot := WithdrawalQueueStorageLocation
        }
    }

    event WithdrawalRequested(
        uint256 indexed requestId, address indexed owner, address indexed receiver, uint256 shares
    );
    event WithdrawalFinalized(uint256 indexed requestId, address indexed receiver, uint256 shares, uint256 assets);

    error NoElementWithIndex(uint256 index);

    function withdrawalRequest(uint128 index) external view returns (WithdrawalRequest memory) {
        return _getWithdrawalRequest(index);
    }

    function _getWithdrawalRequest(uint256 requestId) internal view returns (WithdrawalRequest storage) {
        WithdrawalQueueStorage storage queue = _getWithdrawalQueueStorageData();
        if (requestId > queue.lastRequestId) revert NoElementWithIndex(requestId);

        return queue.items[requestId];
    }

    function _enqueueRequest(uint256 shares, uint256 assets) internal returns (uint256 requestId) {
        WithdrawalQueueStorage storage queue = _getWithdrawalQueueStorageData();
        unchecked {
            requestId = ++queue.lastRequestId;
        }
        queue.items[requestId] = WithdrawalRequest(shares, assets);
    }

    function _removeRequest(uint256 requestId) internal returns (WithdrawalRequest memory request) {
        WithdrawalQueueStorage storage queue = _getWithdrawalQueueStorageData();
        request = queue.items[requestId];
        delete queue.items[requestId];
    }

    function _finalizeRequests(uint256 newLastFinalizedRequestId) internal {
        WithdrawalQueueStorage storage queue = _getWithdrawalQueueStorageData();
        if (queue.lastFinalizedRequestId >= newLastFinalizedRequestId) revert();
        if (queue.lastRequestId < newLastFinalizedRequestId) revert();

        queue.lastFinalizedRequestId = newLastFinalizedRequestId;
    }
}
