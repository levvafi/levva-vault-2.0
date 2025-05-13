// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";
import {IAdapterCallback} from "../../contracts/interfaces/IAdapterCallback.sol";
import {PendleAdapter} from "../../contracts/adapters/pendle/PendleAdapter.sol";

/// @dev Mintable ERC20 token.
contract VaultMock is IAdapterCallback {
    PendleAdapter private s_pendleAdapter;

    constructor(address pendleAdapter) {
        s_pendleAdapter = PendleAdapter(pendleAdapter);
    }

    function adapterCallback(address receiver, address token, uint256 amount, bytes calldata /*data*/ )
        external
        override
    {
        IERC20(token).transfer(receiver, amount);
    }

    function swapExactTokenForPt(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minPtOut
    ) external {
        s_pendleAdapter.swapExactTokenForPt(market, approxParams, tokenInput, minPtOut);
    }

    function swapExactPtForToken(address market, address ptToken, uint256 exactPtIn, TokenOutput calldata tokenOut)
        external
    {
        s_pendleAdapter.swapExactPtForToken(market, ptToken, exactPtIn, tokenOut);
    }

    function addLiquiditySingleToken(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minLpOut
    ) external {
        s_pendleAdapter.addLiquiditySingleToken(market, approxParams, tokenInput, minLpOut);
    }

    function removeLiquiditySingleToken(
        address market,
        address lpToken,
        uint256 lpAmount,
        TokenOutput calldata tokenOut
    ) external {
        s_pendleAdapter.removeLiquiditySingleToken(market, lpToken, lpAmount, tokenOut);
    }
}
