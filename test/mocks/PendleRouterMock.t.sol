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
    uint256 private s_offset;

    function setMarketPtToken(address market, address ptToken) external {
        s_ptTokens[market] = ptToken;
    }

    function addOffset(uint256 offset) external {
        s_offset = offset;
    }

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata, /*guessPtOut*/
        TokenInput calldata input,
        LimitOrderData calldata /*limit*/
    ) external payable returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm) {
        uint256 ptOut = minPtOut - s_offset;
        IERC20(input.tokenIn).transferFrom(msg.sender, address(this), input.netTokenIn);
        IERC20(s_ptTokens[market]).transfer(receiver, ptOut);
        return (ptOut, 0, 0);
    }

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata /*limit*/
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        uint256 tokenOut = output.minTokenOut - s_offset;
        IERC20(s_ptTokens[market]).transferFrom(msg.sender, address(this), exactPtIn);
        IERC20(output.tokenOut).transfer(receiver, tokenOut);
        return (tokenOut, 0, 0);
    }

    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        ApproxParams calldata, /*guessPtReceivedFromSy*/
        TokenInput calldata input,
        LimitOrderData calldata /*limit*/
    ) external payable returns (uint256 netLpOut, uint256 netSyFee, uint256 netSyInterm) {
        uint256 lpOut = minLpOut - s_offset;
        IERC20(input.tokenIn).transferFrom(msg.sender, address(this), input.netTokenIn);
        IERC20(s_ptTokens[market]).transfer(receiver, lpOut);
        return (lpOut, 0, 0);
    }

    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output,
        LimitOrderData calldata /*limit*/
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        uint256 tokenOut = output.minTokenOut - s_offset;
        IERC20(s_ptTokens[market]).transferFrom(msg.sender, address(this), netLpToRemove);
        IERC20(output.tokenOut).transfer(receiver, tokenOut);
        return (tokenOut, 0, 0);
    }
}
