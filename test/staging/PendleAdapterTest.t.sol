// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PendleAdapter} from "../../contracts/adapters/pendle/PendleAdapter.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    SwapType,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";

contract PendleAdapterTest is Test {
    address private constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    PendleAdapter private pendleAdapter;
    address private OWNER = makeAddr("owner");
    address private VAULT = makeAddr("vault-1");

    function setUp() public {
        pendleAdapter = new PendleAdapter(PENDLE_ROUTER, OWNER);
        vm.deal(OWNER, 1 ether);

        vm.skip(block.chainid != 1);
    }

    function test_PT_tETH_29May2025Market_wstETHToken() public {
        address PT_tETH_29May2025Market = 0xBDb8F9729d3194f75fD1A3D9bc4FFe0DDe3A404c;
        address ptToken = 0x84D17Ef6BeC165484c320B852eEB294203e191be;
        address wstETHToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        uint256 amountIn = 10 * 10 ** 18;

        vm.prank(OWNER);
        pendleAdapter.addMarket(VAULT, PT_tETH_29May2025Market, true);

        TokenInput memory tokenInput = _createTokenInputSimple(wstETHToken, amountIn);
        ApproxParams memory approxParams = _createDefaultApproxParams();

        _swapTokenToPt(PT_tETH_29May2025Market, approxParams, tokenInput, ptToken);
    }

    function test_PT_tETH_29May2025Market_swap_tETH_to_pt() public {
        address PT_tETH_29May2025Market = 0xBDb8F9729d3194f75fD1A3D9bc4FFe0DDe3A404c;
        address ptToken = 0x84D17Ef6BeC165484c320B852eEB294203e191be;
        address tETHToken = 0xD11c452fc99cF405034ee446803b6F6c1F6d5ED8;
        uint256 amountIn = 10 * 10 ** 18;

        vm.prank(OWNER);
        pendleAdapter.addMarket(VAULT, PT_tETH_29May2025Market, true);

        TokenInput memory tokenInput = _createTokenInputSimple(tETHToken, amountIn);
        ApproxParams memory approxParams = _createDefaultApproxParams();

        _swapTokenToPt(PT_tETH_29May2025Market, approxParams, tokenInput, ptToken);
    }

    function test_PT_tETH_29May2025Market_swap_UsdcToken_to_Pt() public {
        address PT_tETH_29May2025Market = 0xBDb8F9729d3194f75fD1A3D9bc4FFe0DDe3A404c;
        address ptToken = 0x84D17Ef6BeC165484c320B852eEB294203e191be;
        address usdcToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        vm.prank(OWNER);
        pendleAdapter.addMarket(VAULT, PT_tETH_29May2025Market, true);

        /*
        To get call data use curl below

        curl -X 'GET' \
    'https://api-v2.pendle.finance/core/v1/sdk/1/markets/0xBDb8F9729d3194f75fD1A3D9bc4FFe0DDe3A404c/swap?receiver=0x20bC1b12B486AF80D3B5dc0A2DE6D2CD69Af9bBE&slippage=0.1&enableAggregator=true&tokenIn=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48&tokenOut=0x84D17Ef6BeC165484c320B852eEB294203e191be&amountIn=100000000' \
    -H 'accept: application/json'
        */

        SwapData memory swapData = SwapData({
            swapType: SwapType(1),
            extRouter: 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5,
            extCalldata: hex"e21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000009400000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000d11c452fc99cf405034ee446803b6f6c1f6d5ed8000000000000000000000000888888888889758f76e7103c6cbf23abbf58f946000000000000000000000000000000000000000000000000000000007fffffff00000000000000000000000000000000000000000000000000000000000005e00000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000003600000000000000000000000000000000000000000000000000000000000000040f59b1df7000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000002000000000000000000000000066a9893cc07d91d95644aedd05d03f95e1dba8af0000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba3000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001f4000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004063407a490000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000202a6012894ae5c288ea824cbc8a9bfb26a49b93000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000cd5fe23c85820f7b72d0926fc9b05b43e359b7ee00000000000000000000000000000000000000000000000000c88c6a97c9935900000000000000000000000000000000000000000000000000000001000276a400000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040d90ce491000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000100000000000000000000000000394a1e1b934cb4f4a0dc17bdd592ec078741542f000000000000000000000000cd5fe23c85820f7b72d0926fc9b05b43e359b7ee000000000000000000000000d11c452fc99cf405034ee446803b6f6c1f6d5ed80000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bc2830cfd3b71f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000af87d2205000000000000000000a7662360642149000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000d11c452fc99cf405034ee446803b6f6c1f6d5ed8000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000888888888889758f76e7103c6cbf23abbf58f9460000000000000000000000000000000000000000000000000000000005f5e1000000000000000000000000000000000000000000000000000096a8b9705a1df40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024c7b22536f75726365223a2250656e646c65222c22416d6f756e74496e555344223a223130302e303436333235323530333533222c22416d6f756e744f7574555344223a2230222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223437313138363233323337373432393231222c2254696d657374616d70223a313734353530383032322c22526f7574654944223a2236646538663338302d346664662d346530312d386639302d626430666463633032633933222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a224a4a4c785a754844574d5162637462617337346337667764506c567663515a79783974517459624d2f324d6b4762462f61644b5745703056336a726c683762574554512b7474586334556b2f414a662f574c5459735976304e7a4a62733031574a4a56493234464732634d50535861635a5556672b4b472f7a576372504a474656596f54304473677151635042794d4d2b6d30466f6e554f61556f77726e544c7a4c327262316e654233463664425a4d4470686b72395a643238486f6f3161623547373261515157684f666b46373276582f50484f5243786b45664c5258692f513464525371496263574d2b473476467675336c39394848486a75594f64326d4a41733672705135792b625950687734436b2b35504e7a566865394f38466a346b4f43716b59304c4538644579734f35554a354e4b4d306c70574c5661356f65686b3869477143314e5a526e364e66487866697953413d3d227d7d0000000000000000000000000000000000000000",
            needScale: false
        });

        TokenInput memory usdcTokenInput = TokenInput({
            tokenIn: usdcToken,
            netTokenIn: 100 * 10 ** 6,
            tokenMintSy: 0xD11c452fc99cF405034ee446803b6F6c1F6d5ED8,
            pendleSwap: 0x313e7Ef7d52f5C10aC04ebaa4d33CDc68634c212,
            swapData: swapData
        });

        ApproxParams memory approxParams =
            ApproxParams({guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});

        _swapTokenToPt(PT_tETH_29May2025Market, approxParams, usdcTokenInput, ptToken);
    }

    function test_PT_tETH_29May2025Market_Swap_pt_to_wstETHToken() public {
        address PT_tETH_29May2025Market = 0xBDb8F9729d3194f75fD1A3D9bc4FFe0DDe3A404c;
        address ptToken = 0x84D17Ef6BeC165484c320B852eEB294203e191be;
        address wstETHToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        uint256 amountIn = 1 * 10 ** 18;

        vm.prank(OWNER);
        pendleAdapter.addMarket(VAULT, PT_tETH_29May2025Market, true);

        TokenOutput memory tokenOutput = _createTokenOutputSimple(wstETHToken, 0);

        _swapPtToToken(PT_tETH_29May2025Market, ptToken, amountIn, tokenOutput);
    }

    function test_PT_tETH_29May2025Market_Swap_pt_to_stETHToken() public {
        address PT_tETH_29May2025Market = 0xBDb8F9729d3194f75fD1A3D9bc4FFe0DDe3A404c;
        address ptToken = 0x84D17Ef6BeC165484c320B852eEB294203e191be;
        address stETHToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        uint256 amountIn = 1 * 10 ** 18;

        vm.prank(OWNER);
        pendleAdapter.addMarket(VAULT, PT_tETH_29May2025Market, true);

        TokenOutput memory tokenOutput = _createTokenOutputSimple(stETHToken, 0);

        _swapPtToToken(PT_tETH_29May2025Market, ptToken, amountIn, tokenOutput);
    }

    function test_PT_tETH_29May2025Market_Swap_pt_to_tETHToken() public {
        address PT_tETH_29May2025Market = 0xBDb8F9729d3194f75fD1A3D9bc4FFe0DDe3A404c;
        address ptToken = 0x84D17Ef6BeC165484c320B852eEB294203e191be;
        address tETHToken = 0xD11c452fc99cF405034ee446803b6F6c1F6d5ED8;
        uint256 amountIn = 1 * 10 ** 18;

        vm.prank(OWNER);
        pendleAdapter.addMarket(VAULT, PT_tETH_29May2025Market, true);

        TokenOutput memory tokenOutput = _createTokenOutputSimple(tETHToken, 0);

        _swapPtToToken(PT_tETH_29May2025Market, ptToken, amountIn, tokenOutput);
    }

    function _swapTokenToPt(
        address market,
        ApproxParams memory approxParams,
        TokenInput memory tokenInput,
        address ptToken
    ) private {
        vm.startPrank(VAULT);
        deal(tokenInput.tokenIn, VAULT, tokenInput.netTokenIn);
        IERC20(tokenInput.tokenIn).transfer(address(pendleAdapter), tokenInput.netTokenIn);
        uint256 balanceBefore = IERC20(ptToken).balanceOf(VAULT);

        pendleAdapter.swapExactTokenForPt(market, approxParams, tokenInput, 0);

        uint256 balanceAfter = IERC20(ptToken).balanceOf(VAULT);

        console.log("Swap ", ERC20(tokenInput.tokenIn).symbol(), " to ", ERC20(ptToken).symbol());
        console.log("TokenIn = ", tokenInput.netTokenIn);
        console.log("PTOut = ", balanceAfter - balanceBefore);
    }

    function _swapPtToToken(address market, address ptToken, uint256 ptTokenIn, TokenOutput memory tokenOut) private {
        vm.startPrank(VAULT);
        deal(ptToken, VAULT, ptTokenIn);
        IERC20(ptToken).transfer(address(pendleAdapter), ptTokenIn);
        uint256 balanceBefore = IERC20(tokenOut.tokenOut).balanceOf(VAULT);

        pendleAdapter.swapExactPtForToken(market, ptToken, ptTokenIn, tokenOut);

        uint256 balanceAfter = IERC20(tokenOut.tokenOut).balanceOf(VAULT);

        console.log("Swap ", ERC20(ptToken).symbol(), " to ", ERC20(tokenOut.tokenOut).symbol());
        console.log("PTIn = ", ptTokenIn);
        console.log("TokenOut = ", balanceAfter - balanceBefore);
    }

    function _swapTokenToLp(address market, address token, address LpToken) private {}

    function _swapLpToToken(address market, address token, address LpToken) private {}

    /// @dev Creates a TokenInput struct without using any swap aggregator
    /// @param tokenIn must be one of the SY's tokens in (obtain via `IStandardizedYield#getTokensIn`)
    /// @param netTokenIn amount of token in
    function _createTokenInputSimple(address tokenIn, uint256 netTokenIn) private pure returns (TokenInput memory) {
        return TokenInput({
            tokenIn: tokenIn,
            netTokenIn: netTokenIn,
            tokenMintSy: tokenIn,
            pendleSwap: address(0),
            swapData: _createSwapTypeNoAggregator()
        });
    }

    function _createSwapTypeNoAggregator() private pure returns (SwapData memory) {}

    function _createEmptyLimitOrderData() private pure returns (LimitOrderData memory) {}

    /// @dev Creates default ApproxParams for on-chain approximation
    function _createDefaultApproxParams() private pure returns (ApproxParams memory) {
        return ApproxParams({guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});
    }

    /// @dev Creates a TokenOutput struct without using any swap aggregator
    /// @param tokenOut must be one of the SY's tokens out (obtain via `IStandardizedYield#getTokensOut`)
    /// @param minTokenOut minimum amount of token out
    function _createTokenOutputSimple(address tokenOut, uint256 minTokenOut)
        private
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
}
