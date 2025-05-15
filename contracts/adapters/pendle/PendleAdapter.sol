// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/Extensions/ERC4626Upgradeable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IPMarketFactory} from "@pendle/core-v2/contracts/interfaces/IPMarketFactory.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";

import {IPMarket} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/contracts/interfaces/IPPrincipalToken.sol";
import {IStandardizedYield} from "@pendle/core-v2/contracts/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "@pendle/core-v2/contracts/interfaces/IPYieldToken.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Asserts} from "../../libraries/Asserts.sol";

contract PendleAdapter is IERC165, IAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;

    address private immutable s_pendleRouter;
    address private immutable s_pendleMarketFactory;

    error PendleAdapter__SlippageProtection();
    error PendleAdapter__InvalidPendleMarket(address pendleMarket);

    constructor(address pendleRouter, address pendleMarketFactory) {
        pendleRouter.assertNotZeroAddress();
        pendleMarketFactory.assertNotZeroAddress();

        s_pendleRouter = pendleRouter;
        s_pendleMarketFactory = pendleMarketFactory;
    }

    /// @notice Get the identifier of adapter
    function getAdapterId() external pure returns (bytes4) {
        return 0x94dfa9d4; // bytes4(keccak256("PendleAdapter"))
    }

    /// @notice Implementation of ERC165, supports IAdapter and IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAdapter).interfaceId || interfaceId == type(IERC165).interfaceId;
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
    ) external {
        _ensureIsValidPendleMarket(market);
        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenInput.tokenIn, tokenInput.netTokenIn, "");

        address pendleRouter = s_pendleRouter;
        IERC20(tokenInput.tokenIn).forceApprove(pendleRouter, tokenInput.netTokenIn);

        (uint256 netPtOut,,) = IPAllActionV3(pendleRouter).swapExactTokenForPt(
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
    function swapExactPtForToken(address market, uint256 exactPtIn, TokenOutput calldata tokenOut) external {
        _ensureIsValidPendleMarket(market);
        (, IPPrincipalToken ptToken,) = IPMarket(market).readTokens();

        // transfer exact amount of ptToken from msg.sender to this contract
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(ptToken), exactPtIn, "");

        address pendleRouter = s_pendleRouter;
        IERC20(ptToken).forceApprove(pendleRouter, exactPtIn);

        (uint256 netTokenOut,,) = IPAllActionV3(pendleRouter).swapExactPtForToken(
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
    ) external {
        _ensureIsValidPendleMarket(market);
        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenInput.tokenIn, tokenInput.netTokenIn, "");

        address pendleRouter = s_pendleRouter;
        IERC20(tokenInput.tokenIn).forceApprove(pendleRouter, tokenInput.netTokenIn);

        (uint256 netLpOut,,) = IPAllActionV3(pendleRouter).addLiquiditySingleToken(
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
    function removeLiquiditySingleToken(address market, uint256 lpAmount, TokenOutput calldata tokenOut) external {
        _ensureIsValidPendleMarket(market);
        IAdapterCallback(msg.sender).adapterCallback(address(this), market, lpAmount, "");

        address pendleRouter = s_pendleRouter;
        //market itself is the lp token
        IERC20(market).forceApprove(pendleRouter, lpAmount);

        (uint256 netTokenOut,,) = IPAllActionV3(pendleRouter).removeLiquiditySingleToken(
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
    /// @dev Swap PT for Token if market is expired
    function redeemPt(address market, uint256 ptIn, TokenOutput calldata tokenOut) external {
        _ensureIsValidPendleMarket(market);
        (, IPPrincipalToken ptToken, IPYieldToken ytToken) = IPMarket(market).readTokens();

        // transfer exact amount of ptToken from msg.sender to this contract
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(ptToken), ptIn, "");

        address pendleRouter = s_pendleRouter;
        IERC20(ptToken).forceApprove(pendleRouter, ptIn);

        (uint256 netTokenOut,) =
            IPAllActionV3(pendleRouter).redeemPyToToken(msg.sender, address(ytToken), ptIn, tokenOut);

        if (netTokenOut < tokenOut.minTokenOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    /// @notice Roll over PT from old market to new market
    /// @param oldMarket old pendle market address
    /// @param newMarket new pendle market address
    /// @param ptAmount amount of PT to roll over
    /// @param minNewPtOut minimum amount of new PT to receive
    function rollOverPt(address oldMarket, address newMarket, uint256 ptAmount, uint256 minNewPtOut) external {
        _ensureIsValidPendleMarket(oldMarket);
        _ensureIsValidPendleMarket(newMarket);

        (IStandardizedYield syToken, IPPrincipalToken oldPtToken, IPYieldToken ytToken) =
            IPMarket(oldMarket).readTokens();

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(oldPtToken), ptAmount, "");

        address token = syToken.getTokensOut()[0];

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
        (uint256 netPtOut,,) = IPAllActionV3(pendleRouter).swapExactTokenForPt(
            msg.sender, newMarket, minNewPtOut, _createDefaultApproxParams(), tokenInput, _createEmptyLimitOrderData()
        );

        if (netPtOut < minNewPtOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    /// @dev Creates default ApproxParams for on-chain approximation
    function _createDefaultApproxParams() private pure returns (ApproxParams memory) {
        return ApproxParams({guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});
    }

    function _createEmptyLimitOrderData() private pure returns (LimitOrderData memory) {}

    function _ensureIsValidPendleMarket(address pendleMarket) private view {
        if (!IPMarketFactory(s_pendleMarketFactory).isValidMarket(pendleMarket)) {
            revert PendleAdapter__InvalidPendleMarket(pendleMarket);
        }
    }
}
