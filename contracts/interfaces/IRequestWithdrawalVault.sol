// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IRequestWithdrawalVault is IERC4626 {
    function withdrawalQueue() external view returns (address withdrawalQueue);
    function requestRedeem(uint256 shares) external returns (uint256 requestId);
}
