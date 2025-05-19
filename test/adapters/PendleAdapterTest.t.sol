// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {PendleRouterMock} from "../mocks/PendleRouterMock.t.sol";
import {PendleMarketMock} from "../mocks/PendleMarketMock.t.sol";
import {MintableERC20} from "../mocks/MintableERC20.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PendleAdapter} from "../../contracts/adapters/pendle/PendleAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {PendleSyTokenMock} from "../mocks/PendleSyTokenMock.t.sol";

import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";

contract PendleAdapterTest is Test {
    using Math for uint256;

    LevvaVault public vault;
    PendleRouterMock pendleRouter;
    PendleAdapter public pendleAdapter;

    address public OWNER = makeAddr("OWNER");
    address public USER = makeAddr("USER");

    address public PT_MARKET_1;
    IERC20 public PT_TOKEN_1;
    address public SY_TOKEN_1;

    address public PT_MARKET_2;
    IERC20 public PT_TOKEN_2;
    address public SY_TOKEN_2;

    address public UNKNOWN_MARKET = makeAddr("UNKNOWN_MARKET");

    IERC20 public WETH;
    IERC20 public USDC;
    IERC20 public USDT;
    IERC20 public SOME_TOKEN;

    function setUp() public {
        PT_TOKEN_1 = new MintableERC20("PT_TOKEN_1", "PT_TOKEN_1", 18);
        PT_TOKEN_2 = new MintableERC20("PT_TOKEN_2", "PT_TOKEN_2", 18);

        WETH = new MintableERC20("WETH", "WETH", 18);
        USDC = new MintableERC20("USDC", "USDC", 6);
        USDT = new MintableERC20("USDT", "USDT", 6);
        SOME_TOKEN = new MintableERC20("SOME_TOKEN", "SOME_TOKEN", 18);

        SY_TOKEN_1 = address(new PendleSyTokenMock(address(USDC), "SY_TOKEN_1", "SY_TOKEN_1", 18));
        SY_TOKEN_2 = address(new PendleSyTokenMock(address(USDC), "SY_TOKEN_2", "SY_TOKEN_2", 18));

        PT_MARKET_1 = address(new PendleMarketMock(address(PT_TOKEN_1), SY_TOKEN_1, "PENDLE_LPT", "PENDLE_LPT", 18));
        PT_MARKET_2 = address(new PendleMarketMock(address(PT_TOKEN_2), SY_TOKEN_2, "PENDLE_LPT", "PENDLE_LPT", 18));

        pendleRouter = new PendleRouterMock();

        deal(address(PT_TOKEN_1), address(pendleRouter), 10000e18);
        deal(address(PT_TOKEN_2), address(pendleRouter), 10000e18);
        deal(address(USDC), address(pendleRouter), 10000e6);
        deal(address(USDT), address(pendleRouter), 10000e6);
        deal(address(PT_MARKET_1), address(pendleRouter), 10000e18);
        deal(address(PT_MARKET_2), address(pendleRouter), 10000e18);

        pendleAdapter = new PendleAdapter(address(pendleRouter));

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(USDC), address(WETH));
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(USDT), address(WETH));
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(PT_TOKEN_1), address(WETH));
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(PT_TOKEN_2), address(WETH));
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(PT_MARKET_1), address(WETH));
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(PT_MARKET_2), address(WETH));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, WETH, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );

        vault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));
        vault.addTrackedAsset(address(USDC));
        vault.addTrackedAsset(address(USDT));
        vault.addTrackedAsset(address(PT_TOKEN_1));
        vault.addTrackedAsset(address(PT_TOKEN_2));
        vault.addTrackedAsset(address(PT_MARKET_1));
        vault.addTrackedAsset(address(PT_MARKET_2));

        vault.addAdapter(address(pendleAdapter));

        deal(address(USDC), address(vault), 10000e6);
        deal(address(USDT), address(vault), 10000e6);
        deal(address(SOME_TOKEN), address(vault), 10000e18);
        deal(address(PT_TOKEN_1), address(vault), 10000e18);
        deal(address(PT_TOKEN_2), address(vault), 10000e18);
        deal(address(PT_MARKET_1), address(vault), 10000e18);
        deal(address(PT_MARKET_2), address(vault), 10000e18);

        vm.stopPrank();
    }

    function testGetPendleRouter() public view {
        assertEq(pendleAdapter.getPendleRouter(), address(pendleRouter));
    }

    function testConstructorShouldFailWhenPendleRouterIsZeroAddress() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new PendleAdapter(address(0));
    }

    function testGetAdapterId() public view {
        bytes32 adapterId = bytes32(pendleAdapter.getAdapterId());
        assertEq(adapterId, bytes32(hex"94dfa9d4"), "Adapter ID mismatch");
    }

    function testSupportsInterface() public view {
        assertTrue(pendleAdapter.supportsInterface(type(IAdapter).interfaceId), "IAdapter not supported");
        assertTrue(pendleAdapter.supportsInterface(type(IERC165).interfaceId), "IERC165 not supported");
        assertFalse(
            pendleAdapter.supportsInterface(type(IExternalPositionAdapter).interfaceId),
            "IExternalPositionAdapter should not be supported"
        );
    }

    function testSwapTokenForPtShouldFailWhenPtIsNotTracked() public {
        deal(address(PT_TOKEN_1), address(vault), 0);
        vault.removeTrackedAsset(address(PT_TOKEN_1));
        uint256 tokenIn = 1000e6;
        uint256 minPtOut = 1000e18;

        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, address(PT_TOKEN_1)));
        hoax(address(vault));
        pendleAdapter.swapExactTokenForPt(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minPtOut
        );
    }

    function testSwapTokenForPt() public {
        uint256 ptBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));
        uint256 tokenIn = 1000e6;
        uint256 minPtOut = 1000e18;

        hoax(address(vault));
        pendleAdapter.swapExactTokenForPt(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minPtOut
        );

        uint256 actualPtOut = PT_TOKEN_1.balanceOf(address(vault)) - ptBalanceBefore;

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualPtOut, minPtOut);
        assertEq(USDC.balanceOf(address(vault)), tokenBalanceBefore - tokenIn);
    }

    function testSwapTokenForPtShouldFailWithSlippage() public {
        pendleRouter.addOffset(1);

        uint256 tokenIn = 1000e6;
        uint256 minPtOut = 1000e18;

        hoax(address(vault));
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        pendleAdapter.swapExactTokenForPt(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minPtOut
        );
    }

    function testSwapPtForToken() public {
        uint256 ptBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));
        uint256 ptIn = 1000e18;
        uint256 minTokenOut = 1000e6;

        hoax(address(vault));
        pendleAdapter.swapExactPtForToken(PT_MARKET_1, ptIn, _createTokenOutputSimple(address(USDC), minTokenOut));

        uint256 actualTokenOut = USDC.balanceOf(address(vault)) - tokenBalanceBefore;

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualTokenOut, minTokenOut);
        assertEq(PT_TOKEN_1.balanceOf(address(vault)), ptBalanceBefore - ptIn);
    }

    function testSwapPtForTokenShouldFailWithSlippage() public {
        pendleRouter.addOffset(1);

        uint256 ptIn = 1000e18;
        uint256 minTokenOut = 1000e6;

        hoax(address(vault));
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        pendleAdapter.swapExactPtForToken(PT_MARKET_1, ptIn, _createTokenOutputSimple(address(USDC), minTokenOut));
    }

    function testAddLiquiditySingleToken() public {
        uint256 tokenIn = 1000e6;
        uint256 minLpOut = 1000e18;
        uint256 lpBalanceBefore = IERC20(PT_MARKET_1).balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));

        hoax(address(vault));
        pendleAdapter.addLiquiditySingleToken(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minLpOut
        );

        uint256 actualLpOut = IERC20(PT_MARKET_1).balanceOf(address(vault)) - lpBalanceBefore;

        assertEq(IERC20(PT_MARKET_1).balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualLpOut, minLpOut);
        assertEq(USDC.balanceOf(address(vault)), tokenBalanceBefore - tokenIn);
    }

    function testAddLiquiditySingleTokenShouldFailWithSlippage() public {
        pendleRouter.addOffset(1);

        uint256 tokenIn = 1000e6;
        uint256 minLpOut = 1000e18;

        hoax(address(vault));
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        pendleAdapter.addLiquiditySingleToken(
            PT_MARKET_1, _createDefaultApproxParams(), _createTokenInputSimple(address(USDC), tokenIn), minLpOut
        );
    }

    function testRemoveLiquiditySingleToken() public {
        uint256 lpIn = 1000e18;
        uint256 minTokenOut = 1000e6;
        uint256 lpBalanceBefore = IERC20(PT_MARKET_1).balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));

        hoax(address(vault));
        pendleAdapter.removeLiquiditySingleToken(
            PT_MARKET_1, lpIn, _createTokenOutputSimple(address(USDC), minTokenOut)
        );

        uint256 actualTokenOut = USDC.balanceOf(address(vault)) - tokenBalanceBefore;

        assertEq(IERC20(PT_MARKET_1).balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualTokenOut, minTokenOut);
        assertEq(IERC20(PT_MARKET_1).balanceOf(address(vault)), lpBalanceBefore - lpIn);
    }

    function testRemoveLiquiditySingleTokenShouldFailWithSlippage() public {
        pendleRouter.addOffset(1);

        uint256 lpIn = 1000e18;
        uint256 minTokenOut = 1000e6;

        hoax(address(vault));
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        pendleAdapter.removeLiquiditySingleToken(
            PT_MARKET_1, lpIn, _createTokenOutputSimple(address(USDC), minTokenOut)
        );
    }

    function testRedeemPt() public {
        PendleMarketMock(PT_MARKET_1).setExpired(true);
        uint256 ptBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 tokenBalanceBefore = USDC.balanceOf(address(vault));
        uint256 ptIn = 1000e18;
        uint256 minTokenOut = 1000e6;
        pendleRouter.setRedeemPt(address(PT_TOKEN_1));

        hoax(address(vault));
        pendleAdapter.redeemPt(PT_MARKET_1, ptIn, _createTokenOutputSimple(address(USDC), minTokenOut));

        uint256 actualTokenOut = USDC.balanceOf(address(vault)) - tokenBalanceBefore;

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);

        assertGe(actualTokenOut, minTokenOut);
        assertEq(PT_TOKEN_1.balanceOf(address(vault)), ptBalanceBefore - ptIn);
    }

    function testRedeemPtShouldFailWithSlippage() public {
        PendleMarketMock(PT_MARKET_1).setExpired(true);
        pendleRouter.addOffset(1);

        uint256 ptIn = 1000e18;
        uint256 minTokenOut = 1000e6;
        pendleRouter.setRedeemPt(address(PT_TOKEN_1));

        hoax(address(vault));
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        pendleAdapter.redeemPt(PT_MARKET_1, ptIn, _createTokenOutputSimple(address(USDC), minTokenOut));
    }

    function testRedeemPtShouldFailWhenMarketIsNotExpired() public {
        hoax(address(vault));
        vm.expectRevert(PendleAdapter.PendleAdapter__MarketNotExpired.selector);
        pendleAdapter.redeemPt(PT_MARKET_1, 1000e18, _createTokenOutputSimple(address(USDC), 1000e6));
    }

    function testRollOverPt() public {
        uint256 oldPtBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 newPtBalanceBefore = PT_TOKEN_2.balanceOf(address(vault));
        uint256 ptIn = 1000e18;
        uint256 minNetPtTokenOut = 1000e18;

        pendleRouter.addRollOverOffset(1000e6);

        hoax(address(vault));
        pendleAdapter.rollOverPt(PT_MARKET_1, PT_MARKET_2, address(USDC), ptIn, minNetPtTokenOut);

        uint256 oldPtBalanceAfter = PT_TOKEN_1.balanceOf(address(vault));
        uint256 newPtBalanceAfter = PT_TOKEN_2.balanceOf(address(vault));

        assertEq(oldPtBalanceBefore - oldPtBalanceAfter, ptIn);
        assertGe(newPtBalanceAfter - newPtBalanceBefore, minNetPtTokenOut);

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(PT_TOKEN_2.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);
    }

    function testRollOverPtExpiredMarket() public {
        uint256 oldPtBalanceBefore = PT_TOKEN_1.balanceOf(address(vault));
        uint256 newPtBalanceBefore = PT_TOKEN_2.balanceOf(address(vault));
        uint256 minNetPtTokenOut = 1000e18;
        uint256 ptIn = 100e18;
        PendleMarketMock(PT_MARKET_1).setExpired(true);

        pendleRouter.setRedeemPt(address(PT_TOKEN_1));
        pendleRouter.addRollOverOffset(1000e6);

        hoax(address(vault));
        pendleAdapter.rollOverPt(PT_MARKET_1, PT_MARKET_2, address(USDC), ptIn, minNetPtTokenOut);

        uint256 oldPtBalanceAfter = PT_TOKEN_1.balanceOf(address(vault));
        uint256 newPtBalanceAfter = PT_TOKEN_2.balanceOf(address(vault));

        assertEq(oldPtBalanceBefore - oldPtBalanceAfter, ptIn);
        assertGe(newPtBalanceAfter - newPtBalanceBefore, minNetPtTokenOut);

        assertEq(PT_TOKEN_1.balanceOf(address(pendleAdapter)), 0);
        assertEq(PT_TOKEN_2.balanceOf(address(pendleAdapter)), 0);
        assertEq(USDC.balanceOf(address(pendleAdapter)), 0);
    }

    function testRollOverPtShouldFailWithSlippage() public {
        uint256 ptIn = 1000e18;
        uint256 minNetPtTokenOut = 1000e18;

        pendleRouter.addRollOverOffset(1000e6);
        pendleRouter.addOffset(1);

        hoax(address(vault));
        vm.expectRevert(PendleAdapter.PendleAdapter__SlippageProtection.selector);
        pendleAdapter.rollOverPt(PT_MARKET_1, PT_MARKET_2, address(USDC), ptIn, minNetPtTokenOut);
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

    function _createDefaultApproxParams() private pure returns (ApproxParams memory) {
        return ApproxParams({guessMin: 0, guessMax: type(uint256).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});
    }

    function _createSwapTypeNoAggregator() private pure returns (SwapData memory) {}
}
