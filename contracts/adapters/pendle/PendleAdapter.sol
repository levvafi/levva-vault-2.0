// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";

import {IPSwapAggregator, SwapDataExtra} from "@pendle/core-v2/contracts/router/swap-aggregator/IPSwapAggregator.sol";

import {IPMarket} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/contracts/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "@pendle/core-v2/contracts/interfaces/IPYieldToken.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {IMultiAssetVault} from "../../interfaces/IMultiAssetVault.sol";
import {AdapterBase} from "../AdapterBase.sol";

/// @title Adapter for interaction with Pendle protocol
contract PendleAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("PendleAdapter"));

    address private immutable s_pendleRouter;

    error PendleAdapter__SlippageProtection();
    error PendleAdapter__InvalidPendleMarket(address pendleMarket);
    error PendleAdapter__MarketNotExpired();

    constructor(address pendleRouter) {
        pendleRouter.assertNotZeroAddress();

        s_pendleRouter = pendleRouter;
    }

    /// @notice Get pendle router address
    function getPendleRouter() external view returns (address) {
        return s_pendleRouter;
    }

    /// @notice Swap exact token for PT
    /// @param market pendle market address
    /// @param approxParams approximation parameters
    /// @param tokenInput token input data
    /// @param minPtOut minimum amount of PT to receive
    /// @dev Market should be non expired
    function swapExactTokenForPt(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minPtOut
    ) external returns (uint256 netPtOut) {
        (, IPPrincipalToken ptToken,) = IPMarket(market).readTokens();
        _ensureIsValidAsset(address(ptToken));
        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenInput.tokenIn, tokenInput.netTokenIn);

        address pendleRouter = s_pendleRouter;
        IERC20(tokenInput.tokenIn).forceApprove(pendleRouter, tokenInput.netTokenIn);

        (netPtOut,,) = IPAllActionV3(pendleRouter).swapExactTokenForPt(
            msg.sender, market, minPtOut, approxParams, tokenInput, _createEmptyLimitOrderData()
        );

        if (netPtOut < minPtOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    /// @notice Swap exact PT for token
    /// @param market pendle market address
    /// @param exactPtIn exact amount of PT to swap
    /// @param tokenOut token output data
    /// @dev Market should be non expired
    function swapExactPtForToken(address market, uint256 exactPtIn, TokenOutput calldata tokenOut)
        external
        returns (uint256 netTokenOut)
    {
        _ensureIsValidAsset(tokenOut.tokenOut);
        (, IPPrincipalToken ptToken,) = IPMarket(market).readTokens();

        // transfer exact amount of ptToken from msg.sender to this contract
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(ptToken), exactPtIn);

        address pendleRouter = s_pendleRouter;
        IERC20(ptToken).forceApprove(pendleRouter, exactPtIn);

        (netTokenOut,,) = IPAllActionV3(pendleRouter).swapExactPtForToken(
            msg.sender, market, exactPtIn, tokenOut, _createEmptyLimitOrderData()
        );

        if (netTokenOut < tokenOut.minTokenOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    /// @notice Add liquidity to a pendle market, get LP token in return
    /// @param market pendle market address
    /// @param approxParams approximation parameters
    /// @param tokenInput token input data
    /// @param minLpOut minimum amount of LP token to receive
    function addLiquiditySingleToken(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minLpOut
    ) external returns (uint256 netLpOut) {
        _ensureIsValidAsset(market);

        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenInput.tokenIn, tokenInput.netTokenIn);

        address pendleRouter = s_pendleRouter;
        IERC20(tokenInput.tokenIn).forceApprove(pendleRouter, tokenInput.netTokenIn);

        (netLpOut,,) = IPAllActionV3(pendleRouter).addLiquiditySingleToken(
            msg.sender, market, minLpOut, approxParams, tokenInput, _createEmptyLimitOrderData()
        );

        if (netLpOut < minLpOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    /// @notice Remove liquidity from a pendle market, get token in return
    /// @param market pendle market address
    /// @param lpAmount amount of LP token to remove
    /// @param tokenOut token output data
    function removeLiquiditySingleToken(address market, uint256 lpAmount, TokenOutput calldata tokenOut)
        external
        returns (uint256 netTokenOut)
    {
        _ensureIsValidAsset(tokenOut.tokenOut);

        IAdapterCallback(msg.sender).adapterCallback(address(this), market, lpAmount);

        address pendleRouter = s_pendleRouter;
        //market itself is the lp token
        IERC20(market).forceApprove(pendleRouter, lpAmount);

        (netTokenOut,,) = IPAllActionV3(pendleRouter).removeLiquiditySingleToken(
            msg.sender, market, lpAmount, tokenOut, _createEmptyLimitOrderData()
        );

        //double check the output
        if (netTokenOut < tokenOut.minTokenOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    /// @notice Redeem PT token, get token in return
    /// @param market pendle market address
    /// @param ptIn amount of PT to redeem
    /// @param tokenOut token output data
    /// @dev Works only for expired markets. Swap PT for Token if market is expired
    function redeemPt(address market, uint256 ptIn, TokenOutput calldata tokenOut)
        external
        returns (uint256 netTokenOut)
    {
        _ensureIsValidAsset(tokenOut.tokenOut);
        if (!IPMarket(market).isExpired()) {
            revert PendleAdapter__MarketNotExpired();
        }

        (, IPPrincipalToken ptToken, IPYieldToken ytToken) = IPMarket(market).readTokens();

        // transfer exact amount of ptToken from msg.sender to this contract
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(ptToken), ptIn);

        address pendleRouter = s_pendleRouter;
        IERC20(ptToken).forceApprove(pendleRouter, ptIn);

        (netTokenOut,) = IPAllActionV3(pendleRouter).redeemPyToToken(msg.sender, address(ytToken), ptIn, tokenOut);

        if (netTokenOut < tokenOut.minTokenOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    /// @notice Roll over PT from old market to new market
    /// @dev Works for expired and non expired old markets. Swap an old  Pt for Token, then swap Token for a new Pt
    /// @param oldMarket old pendle market address
    /// @param newMarket new pendle market address
    /// @param token oldMarket token output and new market token input
    /// @param ptAmount amount of PT to roll over
    /// @param minNewPtOut minimum amount of new PT to receive
    function rollOverPt(address oldMarket, address newMarket, address token, uint256 ptAmount, uint256 minNewPtOut)
        external
        returns (uint256 netPtOut)
    {
        (, IPPrincipalToken oldPtToken, IPYieldToken ytToken) = IPMarket(oldMarket).readTokens();
        {
            //avoid stack to deep
            (, IPPrincipalToken newPtToken,) = IPMarket(newMarket).readTokens();
            _ensureIsValidAsset(address(newPtToken));
        }

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(oldPtToken), ptAmount);

        SwapData memory noSwap;
        TokenOutput memory tokenOut = TokenOutput({
            tokenOut: token,
            minTokenOut: 0,
            tokenRedeemSy: token,
            pendleSwap: address(0),
            swapData: noSwap
        });

        address pendleRouter = s_pendleRouter;

        IERC20(oldPtToken).forceApprove(pendleRouter, ptAmount);

        uint256 netTokenOut;
        if (IPMarket(oldMarket).isExpired()) {
            (netTokenOut,) =
                IPAllActionV3(pendleRouter).redeemPyToToken(address(this), address(ytToken), ptAmount, tokenOut);
        } else {
            (netTokenOut,,) = IPAllActionV3(pendleRouter).swapExactPtForToken(
                address(this), oldMarket, ptAmount, tokenOut, _createEmptyLimitOrderData()
            );
        }

        TokenInput memory tokenInput = TokenInput({
            tokenIn: tokenOut.tokenOut,
            netTokenIn: netTokenOut,
            tokenMintSy: tokenOut.tokenOut,
            pendleSwap: address(0),
            swapData: noSwap
        });

        IERC20(tokenOut.tokenOut).forceApprove(pendleRouter, netTokenOut);
        (netPtOut,,) = IPAllActionV3(pendleRouter).swapExactTokenForPt(
            msg.sender, newMarket, minNewPtOut, _createDefaultApproxParams(), tokenInput, _createEmptyLimitOrderData()
        );

        if (netPtOut < minNewPtOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    /// @notice Swap token to token. Not supported PT,YT, LP
    /// @param pendleSwap Address of pendleSwapAggregator
    /// @param swap swap data
    /// @param netSwap swap amount
    function swapTokenToToken(IPSwapAggregator pendleSwap, SwapDataExtra calldata swap, uint256 netSwap)
        external
        returns (uint256)
    {
        _ensureIsValidAsset(address(swap.tokenOut));

        SwapDataExtra[] memory swaps = new SwapDataExtra[](1);
        swaps[0] = swap;

        uint256[] memory netSwaps = new uint256[](1);
        netSwaps[0] = netSwap;

        address pendleRouter = s_pendleRouter;

        IAdapterCallback(msg.sender).adapterCallback(address(this), swap.tokenIn, netSwap);
        IERC20(swap.tokenIn).forceApprove(pendleRouter, netSwap);

        (uint256[] memory netOut) = IPAllActionV3(pendleRouter).swapTokensToTokens(pendleSwap, swaps, netSwaps);
        if (netOut[0] < swap.minOut) {
            revert PendleAdapter__SlippageProtection();
        }

        IERC20(swap.tokenOut).safeTransfer(msg.sender, netOut[0]);
        return netOut[0];
    }

    /// @notice Redeem rewards from a pendle market
    /// @dev This function will ensure that the rewards are valid assets before redeeming them
    function redeemRewards(address pendleMarket) external returns (address[] memory assets, uint256[] memory rewards) {
        assets = IPMarket(pendleMarket).getRewardTokens();
        rewards = IPMarket(pendleMarket).redeemRewards(msg.sender);

        uint256 length = assets.length;
        for (uint256 i = 0; i < length;) {
            if (rewards[i] != 0) {
                _ensureIsValidAsset(assets[i]);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Creates default ApproxParams for on-chain approximation
    function _createDefaultApproxParams() private pure returns (ApproxParams memory) {
        return ApproxParams({guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});
    }

    /// @dev Creates empty LimitOrderData
    function _createEmptyLimitOrderData() private pure returns (LimitOrderData memory) {}
}
