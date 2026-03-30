// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {UniswapV3_02Adapter} from "../../contracts/adapters/uniswap/UniswapV3_02Adapter.sol";
import {ISwapRouter02} from "../../contracts/adapters/uniswap/interfaces/ISwapRouter02.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract UniswapV3_02AdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    address private constant UNISWAP_V3_02_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    UniswapV3_02Adapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(WBTC), address(USDC));

        address levvaVaultImplementation = address(new LevvaVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address levvaVaultFactoryImplementation = address(new LevvaVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            LevvaVaultFactory.initialize.selector, levvaVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy levvaVaultFactoryProxy = new ERC1967Proxy(levvaVaultFactoryImplementation, data);
        LevvaVaultFactory levvaVaultFactory = LevvaVaultFactory(address(levvaVaultFactoryProxy));

        (address deployedVault,) = levvaVaultFactory.deployVault(
            address(USDC),
            "lpName",
            "lpSymbol",
            "withdrawalQueueName",
            "withdrawalQueueSymbol",
            address(0xFEE),
            address(oracle)
        );

        levvaVault = LevvaVault(deployedVault);
        levvaVault.setMaxTrackedAssets(type(uint8).max);

        adapter = new UniswapV3_02Adapter(UNISWAP_V3_02_ROUTER);
        levvaVault.addAdapter(address(adapter));

        levvaVault.addTrackedAsset(address(WBTC));
        deal(address(USDC), address(levvaVault), 10 ** 18);
    }

    function testSwapExactInputV3() public {
        uint256 amountIn = 100_000 * 10 ** 6;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));

        bytes memory path = abi.encodePacked(USDC, uint24(3_000), WBTC);

        ISwapRouter02.ExactInputParams memory params = ISwapRouter02.ExactInputParams({
            path: path,
            recipient: address(levvaVault),
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(levvaVault));
        adapter.swapExactInputV3(params);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(levvaVault));
        assertEq(usdcBalanceBefore - usdcBalanceAfter, amountIn);
        assertGt(WBTC.balanceOf(address(levvaVault)), 0);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactInputV3AllExcept() public {
        deal(address(USDC), address(levvaVault), 105_000 * 10 ** 6);
        uint256 except = 100_000 * 10 ** 6;

        bytes memory path = abi.encodePacked(USDC, uint24(3_000), WBTC);

        ISwapRouter02.ExactInputParams memory params = ISwapRouter02.ExactInputParams({
            path: path,
            recipient: address(levvaVault),
            amountIn: except,
            amountOutMinimum: 0
        });

        vm.prank(address(levvaVault));
        adapter.swapExactInputV3AllExcept(params);

        assertEq(USDC.balanceOf(address(levvaVault)), except);
        assertGt(WBTC.balanceOf(address(levvaVault)), 0);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactInputV3WrongRecipient() public {
        uint128 amountIn = 100_000 * 10 ** 6;
        bytes memory path = abi.encodePacked(USDC, uint24(3_000), WBTC);
        address recipient = address(0x01);

        ISwapRouter02.ExactInputParams memory params = ISwapRouter02.ExactInputParams({
            path: path,
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(levvaVault));
        vm.expectRevert(
            abi.encodeWithSelector(UniswapV3_02Adapter.WrongRecipient.selector, address(levvaVault), recipient)
        );
        adapter.swapExactInputV3(params);
    }

    function testSwapExactOutputV3() public {
        uint256 amountOut = 10 ** 8;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));

        bytes memory path = abi.encodePacked(WBTC, uint24(3_000), USDC);

        ISwapRouter02.ExactOutputParams memory params = ISwapRouter02.ExactOutputParams({
            path: path,
            recipient: address(levvaVault),
            amountOut: amountOut,
            amountInMaximum: USDC.balanceOf(address(levvaVault))
        });

        vm.prank(address(levvaVault));
        adapter.swapExactOutputV3(params);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(levvaVault));
        assertGt(usdcBalanceBefore, usdcBalanceAfter);
        assertEq(WBTC.balanceOf(address(levvaVault)), amountOut);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactOutputV3WrongRecipient() public {
        uint256 amountOut = 10 ** 8;
        bytes memory path = abi.encodePacked(WBTC, uint24(3_000), USDC);
        address recipient = address(0x01);

        ISwapRouter02.ExactOutputParams memory params = ISwapRouter02.ExactOutputParams({
            path: path,
            recipient: recipient,
            amountOut: amountOut,
            amountInMaximum: USDC.balanceOf(address(levvaVault))
        });

        vm.prank(address(levvaVault));
        vm.expectRevert(
            abi.encodeWithSelector(UniswapV3_02Adapter.WrongRecipient.selector, address(levvaVault), recipient)
        );
        adapter.swapExactOutputV3(params);
    }
}
