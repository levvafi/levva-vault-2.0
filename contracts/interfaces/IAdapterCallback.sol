// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAdapterCallback {
    /// @notice Callback should transfer tokens to the receiver (adapter or external router depends on the adapter implementation)
    /// @dev Levva vault should implement this function
    /// @param token Address of token
    /// @param receiver Address of token receiver
    /// @param amount Amount of tokens to transfer
    function adapterCallback(address receiver, address token, uint256 amount) external;
}
