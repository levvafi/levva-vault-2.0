// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

abstract contract WithdrawalRequestQueue {
    /// @dev 'WithdrawalQueueStorageData' storage slot address
    /// @dev keccak256(abi.encode(uint256(keccak256("levva-vault.WithdrawalQueueStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalQueueStorageLocation =
        0x4ff390a5d5a11ce79e4a39c0047f1e548cef89b95e951e10719d61464ab9a900;

    struct WithdrawalRequest {
        /// @dev address of user
        address receiver;
        /// @dev lp amount to burn and exchange for underlying token
        uint256 shares;
    }

    struct WithdrawalQueueStorage {
        /// @dev queue inner starting index. Increased after dequeue
        uint128 start;
        /// @dev queue inner ending index. Increased after enqueue
        uint128 end;
        /// @dev queue items
        mapping(uint128 index => WithdrawalRequest item) items;
    }

    function _getWithdrawalQueueStorageData() private pure returns (WithdrawalQueueStorage storage $) {
        assembly {
            $.slot := WithdrawalQueueStorageLocation
        }
    }

    event WithdrawalRequested(
        uint128 indexed requestId, address indexed owner, address indexed receiver, uint256 shares
    );
    event WithdrawalFinalized(uint128 indexed requestId, address indexed receiver, uint256 shares, uint256 assets);

    error NoElementWithIndex(uint256 index);

    function withdrawalRequest(uint128 index) external view returns (WithdrawalRequest memory) {
        return _getWithdrawalRequest(index);
    }

    function _getWithdrawalRequest(uint128 index) internal view returns (WithdrawalRequest storage) {
        WithdrawalQueueStorage storage queue = _getWithdrawalQueueStorageData();
        uint128 memoryIndex = queue.start + index;
        if (memoryIndex >= queue.end) revert NoElementWithIndex(index);

        return queue.items[memoryIndex];
    }

    function _enqueueWithdraw(address receiver, uint256 shares) internal returns (uint128 requestId) {
        WithdrawalQueueStorage storage queue = _getWithdrawalQueueStorageData();
        unchecked {
            requestId = queue.end++;
        }
        queue.items[requestId] = WithdrawalRequest({receiver: receiver, shares: shares});
    }

    function _dequeueWithdraw() internal returns (uint128 requestId) {
        WithdrawalQueueStorage storage queue = _getWithdrawalQueueStorageData();
        unchecked {
            requestId = queue.start++;
        }
        delete queue.items[requestId];
    }

    function _getWithdrawalQueueStartIndex() internal view returns (uint128) {
        return _getWithdrawalQueueStorageData().start;
    }

    function _getWithdrawalQueueEndIndex() internal view returns (uint128) {
        return _getWithdrawalQueueStorageData().end;
    }
}
