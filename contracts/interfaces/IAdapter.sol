// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAdapter {
    /// @notice Get the identifier of adapter
    /// @dev Levva adapters should implement this function
    function getAdapterId() external returns (bytes4);
}
