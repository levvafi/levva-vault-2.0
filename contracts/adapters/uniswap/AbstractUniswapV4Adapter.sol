// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Asserts} from "../../libraries/Asserts.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {AdapterBase} from "../AdapterBase.sol";

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

abstract contract AbstractUniswapV4Adapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Asserts for address;

    IUniversalRouter public immutable universalRouter;
    IPermit2 public immutable permit2;

    constructor(address _universalRouter, address _permit2) {
        _universalRouter.assertNotZeroAddress();
        _permit2.assertNotZeroAddress();

        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(_permit2);
    }

    function swapExactInputV4(IV4Router.ExactInputParams memory params) external {
        address outputToken = Currency.unwrap(params.path[params.path.length - 1].intermediateCurrency);
        _ensureIsValidAsset(outputToken);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        address inputToken = Currency.unwrap(params.currencyIn);
        IAdapterCallback(msg.sender).adapterCallback(address(this), inputToken, params.amountIn);

        IUniversalRouter router = universalRouter;
        IPermit2 _permit2 = permit2;
        IERC20(inputToken).forceApprove(address(_permit2), params.amountIn);
        _permit2.approve(inputToken, address(router), uint160(params.amountIn), uint48(block.timestamp));

        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(params);
        actionParams[1] = abi.encode(params.currencyIn, params.amountIn);
        actionParams[2] = abi.encode(outputToken, params.amountOutMinimum);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        router.execute(commands, inputs, block.timestamp);
        _sendTokenToVault(outputToken);
    }

    function swapExactOutputV4(IV4Router.ExactOutputParams memory params) external {
        address outputToken = Currency.unwrap(params.currencyOut);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        address inputToken = Currency.unwrap(params.path[0].intermediateCurrency);

        IAdapterCallback(msg.sender).adapterCallback(address(this), inputToken, params.amountInMaximum);

        IUniversalRouter router = universalRouter;
        IPermit2 _permit2 = permit2;
        IERC20(inputToken).forceApprove(address(_permit2), params.amountInMaximum);
        _permit2.approve(inputToken, address(router), uint160(params.amountInMaximum), uint48(block.timestamp));

        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(params);
        actionParams[1] = abi.encode(inputToken, params.amountInMaximum);
        actionParams[2] = abi.encode(params.currencyOut, params.amountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        universalRouter.execute(commands, inputs, block.timestamp);

        IERC20(inputToken).forceApprove(address(router), 0);
        _sendTokenToVault(inputToken);
        _sendTokenToVault(outputToken);
    }

    function _sendTokenToVault(address token) private {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
    }
}
