// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {UniswapAdapter} from "../../contracts/adapters/uniswap/UniswapAdapter.sol";
import {AbstractUniswapV3Adapter} from "../../contracts/adapters/uniswap/AbstractUniswapV3Adapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract UniswapAdapterTest is Test {
    using Math for uint256;

    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant UNISWAP_UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    UniswapAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl));

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(2000, 10 ** 12), address(WETH), address(USDC));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, USDC, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new UniswapAdapter(UNISWAP_V3_ROUTER, UNISWAP_UNIVERSAL_ROUTER);
        levvaVault.addAdapter(address(adapter));

        levvaVault.addTrackedAsset(address(WETH));
        deal(address(USDC), address(levvaVault), 10 ** 18);
    }

    function testSwapExactInputV3() public {
        uint256 amountIn = 1000 * 10 ** 6;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));

        bytes memory path = abi.encodePacked(USDC, uint24(3_000), WETH);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(levvaVault),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(levvaVault));
        adapter.swapExactInputV3(params);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(levvaVault));
        assertEq(usdcBalanceBefore - usdcBalanceAfter, amountIn);
        assertGt(WETH.balanceOf(address(levvaVault)), 0);
    }

    function testSwapExactInputV3NotTrackedAsset() public {
        uint256 amountIn = 1000 * 10 ** 6;
        bytes memory path = abi.encodePacked(USDC, uint24(3_000), USDT);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(levvaVault),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, USDT));
        adapter.swapExactInputV3(params);
    }

    function testSwapExactInputV3WrongRecipient() public {
        uint256 amountIn = 1000 * 10 ** 6;
        bytes memory path = abi.encodePacked(USDC, uint24(3_000), WETH);
        address recipient = address(0x01);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(levvaVault));
        vm.expectRevert(
            abi.encodeWithSelector(AbstractUniswapV3Adapter.WrongRecipient.selector, address(levvaVault), recipient)
        );
        adapter.swapExactInputV3(params);
    }

    function testSwapExactOutputV3() public {
        uint256 amountOut = 1 ether;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));

        bytes memory path = abi.encodePacked(WETH, uint24(3_000), USDC);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: address(levvaVault),
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: USDC.balanceOf(address(levvaVault))
        });

        vm.prank(address(levvaVault));
        adapter.swapExactOutputV3(params);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(levvaVault));
        assertGt(usdcBalanceBefore, usdcBalanceAfter);
        assertEq(WETH.balanceOf(address(levvaVault)), amountOut);
    }

    function testSwapExactOutputV3NotTrackedAsset() public {
        uint256 amountOut = 1 ether;
        bytes memory path = abi.encodePacked(USDT, uint24(3_000), USDC);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: address(levvaVault),
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: USDC.balanceOf(address(levvaVault))
        });

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, USDT));
        adapter.swapExactOutputV3(params);
    }

    function testSwapExactOutputV3WrongRecipient() public {
        uint256 amountOut = 1 ether;
        bytes memory path = abi.encodePacked(WETH, uint24(3_000), USDC);
        address recipient = address(0x01);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: recipient,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: USDC.balanceOf(address(levvaVault))
        });

        vm.prank(address(levvaVault));
        vm.expectRevert(
            abi.encodeWithSelector(AbstractUniswapV3Adapter.WrongRecipient.selector, address(levvaVault), recipient)
        );
        adapter.swapExactOutputV3(params);
    }
}
