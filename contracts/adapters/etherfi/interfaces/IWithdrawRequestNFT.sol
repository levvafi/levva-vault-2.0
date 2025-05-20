// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IWithdrawRequestNFT {
    function claimWithdraw(uint256 requestId) external;

    function isFinalized(uint256 requestId) external view returns (bool);

    function isValid(uint256 requestId) external view returns (bool);
}
