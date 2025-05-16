// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAdapterCallback} from "../../contracts/interfaces/IAdapterCallback.sol";

/// @dev Mintable ERC20 token.
contract AdapterVaultMock is IAdapterCallback {
    mapping(address => uint256) private s_trackedAssets;
    address private s_asset;

    constructor(address _asset) {
        s_asset = _asset;
    }

    function asset() external view returns (address) {
        return s_asset;
    }

    function setAsset(address _asset) external {
        s_asset = _asset;
    }

    function trackedAssetPosition(address _asset) external view returns (uint256) {
        return s_trackedAssets[_asset];
    }

    function setTrackedAsset(address _asset, uint256 position) external {
        s_trackedAssets[_asset] = position;
    }

    function adapterCallback(address receiver, address token, uint256 amount) external override {
        IERC20(token).transfer(receiver, amount);
    }
}
