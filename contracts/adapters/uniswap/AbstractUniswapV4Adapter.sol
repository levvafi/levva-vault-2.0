// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract AbstractUniswapV4Adapter {
    IUniversalRouter public immutable universalRouter;

    constructor(address _universalRouter) {
        universalRouter = IUniversalRouter(_universalRouter);
    }

    function swapExactInputV4(IV4Router.ExactInputParams memory params, uint256 deadline)
        external
        returns (uint256 amountOut)
    {
        // Encode the swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Encode the actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        // Prepare the parameters for each action
        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(params);
        actionParams[1] = abi.encode(params.currencyIn, params.amountIn);
        actionParams[2] = abi.encode(params.path[params.path.length - 1].intermediateCurrency, params.amountOutMinimum);

        // Encode the inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        // Execute the swap
        universalRouter.execute(commands, inputs, deadline);

        // Retrieve the output amount
        address outputToken = Currency.unwrap(params.path[params.path.length - 1].intermediateCurrency);

        amountOut = IERC20(outputToken).balanceOf(address(this));
        require(amountOut >= params.amountOutMinimum, "Insufficient output amount");
    }

    function swapExactOutputV4(IV4Router.ExactOutputParams memory params, uint256 deadline)
        external
        returns (uint256 amountIn)
    {
        // Encode the swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Encode the actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        // Prepare the parameters for each action
        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(params);
        actionParams[1] = abi.encode(params.path[0].intermediateCurrency, params.amountInMaximum);
        actionParams[2] = abi.encode(params.currencyOut, params.amountOut);

        // Encode the inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        // Execute the swap
        universalRouter.execute(commands, inputs, deadline);

        // Retrieve the input amount used
        address inputToken = Currency.unwrap(params.path[0].intermediateCurrency);
        uint256 balanceAfter = IERC20(inputToken).balanceOf(address(this));
        amountIn = params.amountInMaximum - balanceAfter;
        require(amountIn <= params.amountInMaximum, "Exceeded maximum input amount");
    }
}
