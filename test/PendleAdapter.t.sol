// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IAdapter} from "../contracts/interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../contracts/interfaces/IExternalPositionAdapter.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {VaultMock} from "./mocks/VaultMock.t.sol";
import {PendleRouterMock} from "./mocks/PendleRouterMock.t.sol";
import {MintableERC20} from "./mocks/MintableERC20.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PendleAdapter} from "../contracts/adapters/pendle/PendleAdapter.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Asserts} from "../contracts/libraries/Asserts.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";

contract PendleAdapterTest is Test {
    VaultMock public vault;
    PendleRouterMock pendleRouter;
    PendleAdapter public pendleAdapter;

    address public OWNER = makeAddr("OWNER");
    address public USER = makeAddr("USER");

    address public PT_MARKET_1 = makeAddr("PT_MARKET_1");
    IERC20 public PT_TOKEN_1;

    address public PT_MARKET_2 = makeAddr("PT_MARKET_2");
    IERC20 public PT_TOKEN_2;

    address public PT_MARKET_3 = makeAddr("PT_MARKET_3");
    IERC20 public PT_TOKEN_3;

    address public UNKNOWN_MARKET = makeAddr("UNKNOWN_MARKET");

    IERC20 public USDC;
    IERC20 public USDT;
    IERC20 public SOME_TOKEN;

    function setUp() public {
        PT_TOKEN_1 = new MintableERC20("PT_TOKEN_1", "PT_TOKEN_1", 18);
        PT_TOKEN_2 = new MintableERC20("PT_TOKEN_2", "PT_TOKEN_2", 18);
        PT_TOKEN_3 = new MintableERC20("PT_TOKEN_3", "PT_TOKEN_3", 18);

        USDC = new MintableERC20("USDC", "USDC", 6);
        USDT = new MintableERC20("USDT", "USDT", 6);
        SOME_TOKEN = new MintableERC20("SOME_TOKEN", "SOME_TOKEN", 18);

        pendleRouter = new PendleRouterMock();
        pendleRouter.setMarketPtToken(PT_MARKET_1, address(PT_TOKEN_1));
        pendleRouter.setMarketPtToken(PT_MARKET_2, address(PT_TOKEN_2));
        pendleRouter.setMarketPtToken(PT_MARKET_3, address(PT_TOKEN_3));
        pendleRouter.setMarketPtToken(UNKNOWN_MARKET, makeAddr("UNKNOWN_PT_TOKEN"));

        deal(address(PT_TOKEN_1), address(pendleRouter), 10000e18);
        deal(address(PT_TOKEN_2), address(pendleRouter), 10000e18);
        deal(address(PT_TOKEN_3), address(pendleRouter), 10000e18);
        deal(address(USDC), address(pendleRouter), 10000e6);
        deal(address(USDT), address(pendleRouter), 10000e6);

        pendleAdapter = new PendleAdapter(address(pendleRouter), OWNER);

        vault = new VaultMock(address(pendleAdapter));

        deal(address(USDC), address(vault), 10000e6);
        deal(address(USDT), address(vault), 10000e6);
        deal(address(SOME_TOKEN), address(vault), 10000e18);
        deal(address(PT_TOKEN_1), address(vault), 10000e18);
        deal(address(PT_TOKEN_2), address(vault), 10000e18);
        deal(address(PT_TOKEN_3), address(vault), 10000e18);

        vm.startPrank(OWNER);
        pendleAdapter.addMarket(address(vault), PT_MARKET_1, true);
        pendleAdapter.addMarket(address(vault), PT_MARKET_2, true);
        pendleAdapter.addMarket(address(vault), PT_MARKET_3, true);
        vm.stopPrank();
    }

    function testConstructorShouldFailWhenZeroAddress() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new PendleAdapter(address(0), OWNER);
    }

    function test_getAdapterId() public view {
        bytes32 adapterId = bytes32(pendleAdapter.getAdapterId());
        assertEq(adapterId, bytes32(hex"94dfa9d4"), "Adapter ID mismatch");
    }

    function test_supportsInterface() public view {
        assertTrue(pendleAdapter.supportsInterface(type(IAdapter).interfaceId), "IAdapter not supported");
        assertTrue(pendleAdapter.supportsInterface(type(IERC165).interfaceId), "IERC165 not supported");
        assertFalse(
            pendleAdapter.supportsInterface(type(IExternalPositionAdapter).interfaceId),
            "IExternalPositionAdapter should not be supported"
        );
    }

    function testAddMarketShouldFailWhenUnauthorizedAccount() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        pendleAdapter.addMarket(address(vault), PT_MARKET_1, true);
    }

    function testAddMarketShouldFailWhenZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(Asserts.ZeroAddress.selector);
        pendleAdapter.addMarket(address(0), PT_MARKET_1, true);

        vm.expectRevert(Asserts.ZeroAddress.selector);
        pendleAdapter.addMarket(address(vault), address(0), true);
    }

    function testAddMarketShouldRemoveMarketFromVault() public {
        vm.startPrank(OWNER);
        assertTrue(pendleAdapter.getMarketIsAvailable(address(vault), PT_MARKET_1), "Market should be available");

        vm.expectEmit(address(pendleAdapter));
        emit PendleAdapter.MarketAvailabilityUpdated(address(vault), PT_MARKET_1, false);

        pendleAdapter.addMarket(address(vault), PT_MARKET_1, false);
        assertFalse(pendleAdapter.getMarketIsAvailable(address(vault), PT_MARKET_1), "Market should not be available");
    }

    function testAddMarketShouldAddMarketToVault() public {
        vm.startPrank(OWNER);
        assertFalse(
            pendleAdapter.getMarketIsAvailable(address(vault), UNKNOWN_MARKET), "Market should not be available"
        );

        pendleAdapter.addMarket(address(vault), UNKNOWN_MARKET, true);
        assertTrue(pendleAdapter.getMarketIsAvailable(address(vault), UNKNOWN_MARKET), "Market should be available");
    }

    function testGetMarketIsAvailable() public view {
        assertTrue(pendleAdapter.getMarketIsAvailable(address(vault), PT_MARKET_1));
        assertFalse(pendleAdapter.getMarketIsAvailable(address(0), PT_MARKET_2));
        assertFalse(pendleAdapter.getMarketIsAvailable(address(1), address(0)));
    }

    function testSwapTokenForPt() public {
        uint256 ptBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));
        uint256 tokenIn = 1000e6;
        uint256 minPtOut = 1000e18;

        vm.startPrank(USER);
        vault.swapExactTokenForPt(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minPtOut
        );

        uint256 actualPtOut = PT_TOKEN_1.balanceOf(address(vault)) - ptBalanceBefore;

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualPtOut, minPtOut);
        assertEq(USDC.balanceOf(address(vault)), tokenBalanceBefore - tokenIn);
    }

    function testSwapTokenForPtShouldFailWhenMarketNotAvailable() public {
        vm.startPrank(USER);
        vm.expectRevert(PendleAdapter.PendleAdapter__MarketNotAvailable.selector);
        vault.swapExactTokenForPt(
            UNKNOWN_MARKET, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), 1000e6), 1000e18
        );
    }

    function testSwapTokenForPtShouldFailWithSlippage() public {
        pendleRouter.addOffset(1);

        uint256 tokenIn = 1000e6;
        uint256 minPtOut = 1000e18;

        vm.startPrank(USER);
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        vault.swapExactTokenForPt(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minPtOut
        );
    }

    function testSwapPtForToken() public {
        uint256 ptBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));
        uint256 ptIn = 1000e18;
        uint256 minTokenOut = 1000e6;

        vm.startPrank(USER);
        vault.swapExactPtForToken(
            PT_MARKET_1, address(PT_TOKEN_1), ptIn, _createTokenOutputSimple(address(USDC), minTokenOut)
        );

        uint256 actualTokenOut = USDC.balanceOf(address(vault)) - tokenBalanceBefore;

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualTokenOut, minTokenOut);
        assertEq(PT_TOKEN_1.balanceOf(address(vault)), ptBalanceBefore - ptIn);
    }

    function testSwapPtForTokenShouldFailWhenMarketNotAvailable() public {
        vm.startPrank(USER);
        vm.expectRevert(PendleAdapter.PendleAdapter__MarketNotAvailable.selector);
        vault.swapExactPtForToken(
            UNKNOWN_MARKET, address(PT_TOKEN_1), 1000e18, _createTokenOutputSimple(address(USDC), 1000e6)
        );
    }

    function testSwapPtForTokenShouldFailWithSlippage() public {
        pendleRouter.addOffset(1);

        uint256 ptIn = 1000e18;
        uint256 minTokenOut = 1000e6;

        vm.startPrank(USER);
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        vault.swapExactPtForToken(
            PT_MARKET_1, address(PT_TOKEN_1), ptIn, _createTokenOutputSimple(address(USDC), minTokenOut)
        );
    }

    function testAddLiquiditySingleToken() public {
        uint256 tokenIn = 1000e6;
        uint256 minLpOut = 1000e18;
        uint256 lpBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));

        vm.startPrank(USER);
        vault.addLiquiditySingleToken(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minLpOut
        );

        uint256 actualLpOut = PT_TOKEN_1.balanceOf(address(vault)) - lpBalanceBefore;

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualLpOut, minLpOut);
        assertEq(USDC.balanceOf(address(vault)), tokenBalanceBefore - tokenIn);
    }

    function testAddLiquiditySingleTokenShouldFailWhenMarketNotAvailable() public {
        vm.startPrank(USER);
        vm.expectRevert(PendleAdapter.PendleAdapter__MarketNotAvailable.selector);
        vault.addLiquiditySingleToken(
            UNKNOWN_MARKET, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), 1000e6), 1000e18
        );
    }

    function testAddLiquiditySingleTokenShouldFailWithSlippage() public {
        pendleRouter.addOffset(1);

        uint256 tokenIn = 1000e6;
        uint256 minLpOut = 1000e18;

        vm.startPrank(USER);
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        vault.addLiquiditySingleToken(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minLpOut
        );
    }

    function testRemoveLiquiditySingleToken() public {
        uint256 lpIn = 1000e18;
        uint256 minTokenOut = 1000e6;
        uint256 lpBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));

        vm.startPrank(USER);
        vault.removeLiquiditySingleToken(
            PT_MARKET_1, address(PT_TOKEN_1), lpIn, _createTokenOutputSimple(address(USDC), minTokenOut)
        );

        uint256 actualTokenOut = USDC.balanceOf(address(vault)) - tokenBalanceBefore;

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualTokenOut, minTokenOut);
        assertEq(PT_TOKEN_1.balanceOf(address(vault)), lpBalanceBefore - lpIn);
    }

    function testRemoveLiquiditySingleTokenShouldFailWhenMarketNotAvailable() public {
        vm.startPrank(USER);
        vm.expectRevert(PendleAdapter.PendleAdapter__MarketNotAvailable.selector);
        vault.removeLiquiditySingleToken(
            UNKNOWN_MARKET, address(PT_TOKEN_1), 1000e18, _createTokenOutputSimple(address(USDC), 1000e6)
        );
    }

    function testRemoveLiquiditySingleTokenShouldFailWithSlippage() public {
        pendleRouter.addOffset(1);

        uint256 lpIn = 1000e18;
        uint256 minTokenOut = 1000e6;

        vm.startPrank(USER);
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        vault.removeLiquiditySingleToken(
            PT_MARKET_1, address(PT_TOKEN_1), lpIn, _createTokenOutputSimple(address(USDC), minTokenOut)
        );
    }

    function _createTokenInputSimple(address tokenIn, uint256 netTokenIn) private pure returns (TokenInput memory) {
        return TokenInput({
            tokenIn: tokenIn,
            netTokenIn: netTokenIn,
            tokenMintSy: tokenIn,
            pendleSwap: address(0),
            swapData: _createSwapTypeNoAggregator()
        });
    }

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

    function _createEmptyLimitOrderData() private pure returns (LimitOrderData memory) {}

    /// @dev Creates default ApproxParams for on-chain approximation
    function _createDefaultApproxParams() private pure returns (ApproxParams memory) {
        return ApproxParams({guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});
    }

    function _createSwapTypeNoAggregator() private pure returns (SwapData memory) {}
}
