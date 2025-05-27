// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @title Interface lido WithdrawalQueue
/// @dev https://github.com/lidofinance/lido-dao/blob/5fcedc6e9a9f3ec154e69cff47c2b9e25503a78a/contracts/0.8.9/WithdrawalQueue.sol
interface ILidoWithdrawalQueue {
    /// @notice output format struct for `_getWithdrawalStatus()` method
    struct WithdrawalRequestStatus {
        /// @notice stETH token amount that was locked on withdrawal queue for this request
        uint256 amountOfStETH;
        /// @notice amount of stETH shares locked on withdrawal queue for this request
        uint256 amountOfShares;
        /// @notice address that can claim or transfer this request
        address owner;
        /// @notice timestamp of when the request was created, in seconds
        uint256 timestamp;
        /// @notice true, if request is finalized
        bool isFinalized;
        /// @notice true, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);

    function claimWithdrawal(uint256 _requestId) external;

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);

    /// @notice Returns amount of ether available for claim for each provided request id
    /// @param _requestIds array of request ids
    /// @param _hints checkpoint hints. can be found with `findCheckpointHints(_requestIds, 1, getLastCheckpointIndex())`
    /// @return claimableEthValues amount of claimable ether for each request, amount is equal to 0 if request
    ///  is not finalized or already claimed
    function getClaimableEther(uint256[] calldata _requestIds, uint256[] calldata _hints)
        external
        view
        returns (uint256[] memory claimableEthValues);

    function getLastRequestId() external view returns (uint256);

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function finalize(uint256 _lastIdToFinalize, uint256 _maxShareRate) external payable;

    function FINALIZE_ROLE() external view returns (bytes32);

    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function unfinalizedStETH() external view returns (uint256);
}
