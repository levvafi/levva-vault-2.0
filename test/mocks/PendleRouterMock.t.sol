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

/// @dev Mintable ERC20 token.
contract PendleRouterMock {
    mapping(address market => address ptToken) private s_ptTokens;

    function setMarketPtToken(address market, address ptToken) external {
        s_ptTokens[market] = ptToken;
    }

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata, /*guessPtOut*/
        TokenInput calldata input,
        LimitOrderData calldata /*limit*/
    ) external payable returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm) {
        IERC20(input.tokenIn).transferFrom(msg.sender, address(this), input.netTokenIn);
        IERC20(s_ptTokens[market]).transfer(receiver, minPtOut);
        return (minPtOut, 0, 0);
    }

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata /*limit*/
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        IERC20(s_ptTokens[market]).transferFrom(msg.sender, address(this), exactPtIn);
        IERC20(output.tokenOut).transfer(receiver, output.minTokenOut);
        return (output.minTokenOut, 0, 0);
    }

    function addLiquiditySingleTokenSimple(
        address receiver,
        address market,
        uint256 minLpOut,
        TokenInput calldata input
    ) external payable returns (uint256 netLpOut, uint256 netSyFee, uint256 netSyInterm) {
        IERC20(input.tokenIn).transferFrom(msg.sender, address(this), input.netTokenIn);
        IERC20(s_ptTokens[market]).transfer(receiver, minLpOut);
        return (minLpOut, 0, 0);
    }

    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output,
        LimitOrderData calldata /*limit*/
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        IERC20(s_ptTokens[market]).transferFrom(msg.sender, address(this), netLpToRemove);
        IERC20(output.tokenOut).transfer(receiver, output.minTokenOut);
        return (output.minTokenOut, 0, 0);
    }
}
