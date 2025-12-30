// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";

contract OriginETHTechAdapter is AdapterBase {
    using Asserts for address;
    using SafeERC20 for IERC4626;

    bytes4 public constant getAdapterId = bytes4(keccak256("OriginETHTechAdapter"));

    IERC4626 public immutable wrappedOETH;

    constructor(address _wrappedOETH) {
        _wrappedOETH.assertNotZeroAddress();
        wrappedOETH = IERC4626(_wrappedOETH);
    }

    function unwrap(uint256 wrappedOETHAmount) external returns (uint256) {
        return _unwrap(wrappedOETH, wrappedOETHAmount);
    }

    function unwrapAllExcept(uint256 wrappedOETHExceptAmount) external returns (uint256) {
        IERC4626 _wrappedOETH = wrappedOETH;
        uint256 wrappedOETHAmount = _wrappedOETH.balanceOf(msg.sender) - wrappedOETHExceptAmount;
        return _unwrap(_wrappedOETH, wrappedOETHAmount);
    }

    function _unwrap(IERC4626 _wrappedOETH, uint256 wrappedOETHAmount) private returns (uint256 oETHAmount) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_wrappedOETH), wrappedOETHAmount);
        oETHAmount = _wrappedOETH.redeem(wrappedOETHAmount, msg.sender, address(this));
    }
}
