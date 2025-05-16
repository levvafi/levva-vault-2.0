// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PendleAdapter} from "../../../../contracts/adapters/pendle/PendleAdapter.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    SwapType,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";
import {IPMarket} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/contracts/interfaces/IPPrincipalToken.sol";
import {PendleAdapterVaultMock} from "../../../mocks/PendleAdapterVaultMock.t.sol";

abstract contract PendleAdapterTestBase is Test {
    address internal constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    PendleAdapter internal pendleAdapter;
    address internal OWNER = makeAddr("owner");
    PendleAdapterVaultMock internal vault;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl));
        vm.skip(block.chainid != 1, "Only mainnet fork test");

        pendleAdapter = new PendleAdapter(PENDLE_ROUTER);
        vm.deal(OWNER, 1 ether);

        vault = new PendleAdapterVaultMock(address(pendleAdapter), address(0));
    }

    function _swapTokenToPt(
        address market,
        ApproxParams memory approxParams,
        TokenInput memory tokenInput,
        address ptToken
    ) internal {
        deal(tokenInput.tokenIn, address(vault), tokenInput.netTokenIn);
        vault.setTrackedAsset(ptToken, 1);
        uint256 balanceBefore = IERC20(ptToken).balanceOf(address(vault));

        vault.swapExactTokenForPt(market, approxParams, tokenInput, 0);

        uint256 balanceAfter = IERC20(ptToken).balanceOf(address(vault));

        console.log("Swap ", ERC20(tokenInput.tokenIn).symbol(), " to ", ERC20(ptToken).symbol());
        console.log("TokenIn = ", tokenInput.netTokenIn);
        console.log("PTOut = ", balanceAfter - balanceBefore);
    }

    function _swapPtToToken(address market, address ptToken, uint256 ptTokenIn, TokenOutput memory tokenOut) internal {
        deal(ptToken, address(vault), ptTokenIn);
        vault.setTrackedAsset(tokenOut.tokenOut, 1);
        uint256 balanceBefore = IERC20(tokenOut.tokenOut).balanceOf(address(vault));

        vault.swapExactPtForToken(market, ptTokenIn, tokenOut);

        uint256 balanceAfter = IERC20(tokenOut.tokenOut).balanceOf(address(vault));

        console.log("Swap ", ERC20(ptToken).symbol(), " to ", ERC20(tokenOut.tokenOut).symbol());
        console.log("PTIn = ", ptTokenIn);
        console.log("TokenOut = ", balanceAfter - balanceBefore);
    }

    function _redeemPt(address market, address ptToken, uint256 ptTokenIn, TokenOutput memory tokenOut) internal {
        deal(ptToken, address(vault), ptTokenIn);
        vault.setTrackedAsset(tokenOut.tokenOut, 1);
        uint256 balanceBefore = IERC20(tokenOut.tokenOut).balanceOf(address(vault));

        vault.redeemPt(market, ptTokenIn, tokenOut);

        uint256 balanceAfter = IERC20(tokenOut.tokenOut).balanceOf(address(vault));

        console.log("Redeem Pt ", ERC20(ptToken).symbol(), " to ", ERC20(tokenOut.tokenOut).symbol());
        console.log("PTIn = ", ptTokenIn);
        console.log("TokenOut = ", balanceAfter - balanceBefore);
    }

    function _addLiquidity(address market, ApproxParams memory approxParams, TokenInput memory tokenInput) internal {
        deal(tokenInput.tokenIn, address(vault), tokenInput.netTokenIn);
        vault.setTrackedAsset(market, 1);
        uint256 balanceBefore = IERC20(market).balanceOf(address(vault));

        vault.addLiquiditySingleToken(market, approxParams, tokenInput, 0);

        uint256 balanceAfter = IERC20(market).balanceOf(address(vault));

        console.log("Swap ", ERC20(tokenInput.tokenIn).symbol(), " to ", ERC20(market).symbol());
        console.log("TokenIn = ", tokenInput.netTokenIn);
        console.log("LPOut = ", balanceAfter - balanceBefore);
    }

    function _removeLiquidity(address market, uint256 lpAmount, TokenOutput memory tokenOut) internal {
        deal(market, address(vault), lpAmount);
        vault.setTrackedAsset(tokenOut.tokenOut, 1);
        uint256 balanceBefore = IERC20(tokenOut.tokenOut).balanceOf(address(vault));

        vault.removeLiquiditySingleToken(market, lpAmount, tokenOut);

        uint256 balanceAfter = IERC20(tokenOut.tokenOut).balanceOf(address(vault));

        console.log("Swap ", ERC20(market).symbol(), " to ", ERC20(tokenOut.tokenOut).symbol());
        console.log("LPIn = ", lpAmount);
        console.log("TokenOut = ", balanceAfter - balanceBefore);
    }

    function _rollOverPt(address oldMarket, address newMarket, address token, uint256 ptAmount, uint256 minNewPtOut)
        internal
    {
        address oldPt = _getPt(oldMarket);
        address newPt = _getPt(newMarket);
        deal(oldPt, address(vault), ptAmount);
        vault.setTrackedAsset(newPt, 1);

        vault.rollOverPt(oldMarket, newMarket, token, ptAmount, minNewPtOut);

        uint256 newPtBalance = IERC20(_getPt(newMarket)).balanceOf(address(vault));
        console.log("Rolled over ", ERC20(oldPt).symbol(), " to ", ERC20(newPt).symbol());
        console.log("Send = ", ptAmount);
        console.log("Received = ", newPtBalance);
    }

    /// @dev Creates a TokenInput struct without using any swap aggregator
    /// @param tokenIn must be one of the SY's tokens in (obtain via `IStandardizedYield#getTokensIn`)
    /// @param netTokenIn amount of token in
    function _createTokenInputSimple(address tokenIn, uint256 netTokenIn) internal pure returns (TokenInput memory) {
        return TokenInput({
            tokenIn: tokenIn,
            netTokenIn: netTokenIn,
            tokenMintSy: tokenIn,
            pendleSwap: address(0),
            swapData: _createSwapTypeNoAggregator()
        });
    }

    function _createSwapTypeNoAggregator() internal pure returns (SwapData memory) {}

    function _createEmptyLimitOrderData() internal pure returns (LimitOrderData memory) {}

    /// @dev Creates default ApproxParams for on-chain approximation
    function _createDefaultApproxParams() internal pure returns (ApproxParams memory) {
        return ApproxParams({guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});
    }

    /// @dev Creates a TokenOutput struct without using any swap aggregator
    /// @param tokenOut must be one of the SY's tokens out (obtain via `IStandardizedYield#getTokensOut`)
    /// @param minTokenOut minimum amount of token out
    function _createTokenOutputSimple(address tokenOut, uint256 minTokenOut)
        internal
        pure
        returns (TokenOutput memory)
    {
        return TokenOutput({
            tokenOut: tokenOut,
            minTokenOut: minTokenOut,
            tokenRedeemSy: tokenOut,
            pendleSwap: address(0),
            swapData: _createSwapTypeNoAggregator()
        });
    }

    function _getPt(address market) internal view returns (address) {
        (, IPPrincipalToken ptToken,) = IPMarket(market).readTokens();
        return address(ptToken);
    }
}
