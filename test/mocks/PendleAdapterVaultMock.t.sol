// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";
import {PendleAdapter} from "../../contracts/adapters/pendle/PendleAdapter.sol";
import {AdapterVaultMock} from "./AdapterVaultMock.t.sol";

/// @dev Mintable ERC20 token.
contract PendleAdapterVaultMock is AdapterVaultMock {
    PendleAdapter private s_pendleAdapter;
    mapping(address => uint256) private s_trackedAssets;
    address private s_asset;

    constructor(address pendleAdapter, address _asset) AdapterVaultMock(_asset) {
        s_pendleAdapter = PendleAdapter(pendleAdapter);
    }

    function swapExactTokenForPt(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minPtOut
    ) external {
        s_pendleAdapter.swapExactTokenForPt(market, approxParams, tokenInput, minPtOut);
    }

    function swapExactPtForToken(address market, uint256 exactPtIn, TokenOutput calldata tokenOut) external {
        s_pendleAdapter.swapExactPtForToken(market, exactPtIn, tokenOut);
    }

    function addLiquiditySingleToken(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minLpOut
    ) external {
        s_pendleAdapter.addLiquiditySingleToken(market, approxParams, tokenInput, minLpOut);
    }

    function removeLiquiditySingleToken(address market, uint256 lpAmount, TokenOutput calldata tokenOut) external {
        s_pendleAdapter.removeLiquiditySingleToken(market, lpAmount, tokenOut);
    }

    function rollOverPt(address oldMarket, address newMarket, address token, uint256 ptAmount, uint256 minNewPtOut)
        external
    {
        s_pendleAdapter.rollOverPt(oldMarket, newMarket, token, ptAmount, minNewPtOut);
    }

    function redeemPt(address market, uint256 ptIn, TokenOutput calldata tokenOut) external {
        s_pendleAdapter.redeemPt(market, ptIn, tokenOut);
    }
}
