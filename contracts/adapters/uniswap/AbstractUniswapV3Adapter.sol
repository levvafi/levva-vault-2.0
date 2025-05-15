// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Asserts} from "../../libraries/Asserts.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {AdapterBase} from "../AdapterBase.sol";

abstract contract AbstractUniswapV3Adapter is AdapterBase {
    using Asserts for address;
    using SafeERC20 for IERC20;

    ISwapRouter public immutable uniswapV3Router;

    error WrongRecipient(address vault, address recipient);

    constructor(address _router) {
        _router.assertNotZeroAddress();
        uniswapV3Router = ISwapRouter(_router);
    }

    function swapExactInputV3(ISwapRouter.ExactInputParams calldata params) external {
        if (params.recipient != msg.sender) revert WrongRecipient(msg.sender, params.recipient);

        (address inputToken, address outputToken) = decodeTokens(params.path);
        _ensureIsValidAsset(outputToken);

        IAdapterCallback(msg.sender).adapterCallback(address(this), inputToken, params.amountIn);
        ISwapRouter router = uniswapV3Router;
        IERC20(inputToken).forceApprove(address(router), params.amountIn);
        router.exactInput(params);
    }

    function swapExactOutputV3(ISwapRouter.ExactOutputParams calldata params) external {
        if (params.recipient != msg.sender) revert WrongRecipient(msg.sender, params.recipient);

        (address outputToken, address inputToken) = decodeTokens(params.path);
        _ensureIsValidAsset(outputToken);

        IAdapterCallback(msg.sender).adapterCallback(address(this), inputToken, params.amountInMaximum);

        ISwapRouter router = uniswapV3Router;
        IERC20(inputToken).forceApprove(address(router), params.amountInMaximum);
        router.exactOutput(params);
        IERC20(inputToken).forceApprove(address(router), 0);
        IERC20(inputToken).safeTransfer(msg.sender, IERC20(inputToken).balanceOf(address(this)));
    }

    function decodeTokens(bytes memory path) private pure returns (address firstToken, address lastToken) {
        uint256 offset = path.length - 20;
        assembly {
            firstToken := div(mload(add(add(path, 0x20), 0)), 0x1000000000000000000000000)
            lastToken := div(mload(add(add(path, 0x20), offset)), 0x1000000000000000000000000)
        }
    }
}
