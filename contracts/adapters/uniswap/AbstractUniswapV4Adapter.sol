// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Asserts} from "../../libraries/Asserts.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {AdapterBase} from "../AdapterBase.sol";

abstract contract AbstractUniswapV4Adapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Asserts for address;

    IUniversalRouter public immutable universalRouter;
    IAllowanceTransfer public immutable permit2;

    constructor(address _universalRouter, address _permit2) {
        _universalRouter.assertNotZeroAddress();
        _permit2.assertNotZeroAddress();

        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IAllowanceTransfer(_permit2);
    }

    function swapExactInputV4(IV4Router.ExactInputParams calldata params) external {
        address outputToken = Currency.unwrap(params.path[params.path.length - 1].intermediateCurrency);
        _ensureIsValidAsset(outputToken);

        address inputToken = Currency.unwrap(params.currencyIn);
        IAdapterCallback(msg.sender).adapterCallback(address(this), inputToken, params.amountIn);

        IUniversalRouter _universalRouter = universalRouter;
        _permit2Approve(inputToken, address(universalRouter), params.amountIn);

        _universalRouter.execute(_getSwapCommandByteArray(), _getExecuteInputs(params), block.timestamp);
        _sendTokenToVault(outputToken);
    }

    function swapExactOutputV4(IV4Router.ExactOutputParams calldata params) external {
        address outputToken = Currency.unwrap(params.currencyOut);
        _ensureIsValidAsset(outputToken);

        address inputToken = Currency.unwrap(params.path[0].intermediateCurrency);
        IAdapterCallback(msg.sender).adapterCallback(address(this), inputToken, params.amountInMaximum);

        IUniversalRouter _universalRouter = universalRouter;
        _permit2Approve(inputToken, address(universalRouter), params.amountInMaximum);

        universalRouter.execute(_getSwapCommandByteArray(), _getExecuteInputs(params), block.timestamp);
        IERC20(inputToken).forceApprove(address(_universalRouter), 0);

        _sendTokenToVault(inputToken);
        _sendTokenToVault(outputToken);
    }

    function _permit2Approve(address token, address spender, uint256 amount) private {
        IAllowanceTransfer _permit2 = permit2;
        IERC20(token).forceApprove(address(_permit2), amount);
        _permit2.approve(token, spender, uint160(amount), uint48(block.timestamp));
    }

    function _sendTokenToVault(address token) private {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
    }

    function _getSwapCommandByteArray() private pure returns (bytes memory) {
        return abi.encodePacked(uint8(Commands.V4_SWAP));
    }

    function _getExecuteInputs(IV4Router.ExactInputParams calldata params)
        private
        pure
        returns (bytes[] memory inputs)
    {
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(params);
        actionParams[1] = abi.encode(params.currencyIn, params.amountIn);
        actionParams[2] = abi.encode(params.path[params.path.length - 1].intermediateCurrency, params.amountOutMinimum);

        inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);
    }

    function _getExecuteInputs(IV4Router.ExactOutputParams calldata params)
        private
        pure
        returns (bytes[] memory inputs)
    {
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(params);
        actionParams[1] = abi.encode(params.path[0].intermediateCurrency, params.amountInMaximum);
        actionParams[2] = abi.encode(params.currencyOut, params.amountOut);

        inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);
    }
}
