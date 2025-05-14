// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMultiAssetVault {
    function trackedAssetPosition(address trackedAsset) external view returns (uint256);
}
