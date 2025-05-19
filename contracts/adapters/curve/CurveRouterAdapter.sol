// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {ICurveRouterNg} from "./ICurveRouterNg.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";

contract CurveRouterAdapter is AdapterBase {
    using Asserts for address;
    using SafeERC20 for IERC20;

    bytes4 public constant getAdapterId = bytes4(keccak256("CurveRouterAdapter"));

    ICurveRouterNg public immutable s_curveRouter;

    error CurveRouterAdapter__SlippageProtection();

    constructor(address curveRouter) {
        curveRouter.assertNotZeroAddress();
        s_curveRouter = ICurveRouterNg(curveRouter);
    }

    ///@notice Exchange exact amount of token for another token
    ///@dev Receiver of output token is msg.sender
    ///@param route Array of [initial token, pool, token, pool, token, ...]
    ///              The array is iterated until a pool address of 0x00, then the last
    ///              given token is transferred to `_receiver`
    ///@param swapParams Multidimensional array of [i, j, swap_type, pool_type] where
    ///                    i is the index of input token
    ///                    j is the index of output token
    ///                    The swap_type should be:
    ///                    1. for `exchange`,
    ///                    2. for `exchange_underlying` (stable-ng metapools),
    ///                    3. -- legacy --
    ///                    4. for coin -> LP token "exchange" (actually `add_liquidity`),
    ///                    5. -- legacy --
    ///                    6. for LP token -> coin "exchange" (actually `remove_liquidity_one_coin`)
    ///                    7. -- legacy --
    ///                    8. for ETH <-> WETH
    ///                    pool_type: 10 - stable-ng, 20 - twocrypto-ng, 30 - tricrypto-ng, 4 - llamma
    ///@param amount The amount of input token (`_route[0]`) to be sent.
    ///@param minDy The minimum amount received after the final swap.
    ///@param pools Array of pools for swaps via zap contracts. This parameter is only needed for swap_type = 3.
    function exchange(
        address[11] memory route,
        uint256[5][5] memory swapParams,
        uint256 amount,
        uint256 minDy,
        address[5] memory pools
    ) external returns (uint256 amountOut) {
        address tokenIn = route[0];
        address tokenOut = route[10]; // assume last token is output token
        if (tokenOut == address(0)) {
            unchecked {
                for (uint256 i = 3; i < 11; ++i) {
                    if (route[i] == address(0)) {
                        tokenOut = route[i - 1];
                        break;
                    }
                }
            }
        }

        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenIn, amount);
        _ensureIsValidAsset(tokenOut);

        ICurveRouterNg curveRouter = s_curveRouter;
        IERC20(tokenIn).forceApprove(address(curveRouter), amount);
        amountOut = curveRouter.exchange(route, swapParams, amount, minDy, pools, msg.sender);

        if (amountOut < minDy) {
            revert CurveRouterAdapter__SlippageProtection();
        }
    }
}
