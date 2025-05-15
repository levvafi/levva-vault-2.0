// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {UniswapAdapter} from "../../contracts/adapters/uniswap/UniswapAdapter.sol";
import {AbstractUniswapV3Adapter} from "../../contracts/adapters/uniswap/AbstractUniswapV3Adapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {IUSDC} from "../interfaces/IUSDC.t.sol";

contract UniswapAdapterTest is Test {
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUSDC private constant USDC = IUSDC(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    UniswapAdapter private adapter; // = new UniswapAdapter(UNISWAP_V3_ROUTER);
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, IERC20(USDC), "lpName", "lpSymbol", address(0xFEE), address(0x1)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));
        adapter = new UniswapAdapter(UNISWAP_V3_ROUTER);

        levvaVault.addTrackedAsset(address(WETH));

        address masterMinter = USDC.masterMinter();

        vm.prank(masterMinter);
        USDC.configureMinter(masterMinter, type(uint256).max);

        vm.prank(masterMinter);
        // TODO: replace with levva vault
        USDC.mint(address(adapter), 10 ** 18);
    }

    function testSwapExactInputV3() public {
        uint256 amountIn = 1000 * 10 ** 6;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(adapter));

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

        uint256 usdcBalanceAfter = USDC.balanceOf(address(adapter));
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
        uint256 usdcBalanceBefore = USDC.balanceOf(address(adapter));

        bytes memory path = abi.encodePacked(WETH, uint24(3_000), USDC);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: address(levvaVault),
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: USDC.balanceOf(address(adapter))
        });

        vm.prank(address(levvaVault));
        adapter.swapExactOutputV3(params);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(adapter));
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
            amountInMaximum: USDC.balanceOf(address(adapter))
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
            amountInMaximum: USDC.balanceOf(address(adapter))
        });

        vm.prank(address(levvaVault));
        vm.expectRevert(
            abi.encodeWithSelector(AbstractUniswapV3Adapter.WrongRecipient.selector, address(levvaVault), recipient)
        );
        adapter.swapExactOutputV3(params);
    }
}
