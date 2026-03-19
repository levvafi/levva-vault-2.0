// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOETHVault {
    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        uint40 timestamp;
        uint128 amount;
        uint128 queued;
    }

    function mint(address asset, uint256 amount, uint256 minimumOethAmount) external;

    function requestWithdrawal(uint256 amount) external returns (uint256 requestId, uint256 queued);

    function claimWithdrawal(uint256 requestId) external returns (uint256 amount);

    function withdrawalClaimDelay() external view returns (uint256);

    function withdrawalQueueMetadata()
        external
        view
        returns (uint128 queued, uint128 claimable, uint128 claimed, uint128 nextWithdrawalIndex);

    function withdrawalRequests(uint256 requestId) external view returns (WithdrawalRequest memory);

    function asset() external view returns (address);
}
