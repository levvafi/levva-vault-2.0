// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {UniswapV4Adapter} from "../../contracts/adapters/uniswap/UniswapV4Adapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract UniswapAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    address private constant UNISWAP_UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    UniswapV4Adapter private adapter;
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

        adapter = new UniswapV4Adapter(UNISWAP_UNIVERSAL_ROUTER, PERMIT2);
        levvaVault.addAdapter(address(adapter));

        levvaVault.addTrackedAsset(address(WBTC));
        deal(address(USDC), address(levvaVault), 10 ** 18);
    }

    function testSwapExactInputV4() public {
        uint128 amountIn = 100_000 * 10 ** 6;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(address(WBTC)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)),
            hookData: ""
        });

        IV4Router.ExactInputParams memory params = IV4Router.ExactInputParams({
            path: path,
            currencyIn: Currency.wrap(address(USDC)),
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(levvaVault));
        adapter.swapExactInputV4(params, block.timestamp);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(levvaVault));
        assertEq(usdcBalanceBefore - usdcBalanceAfter, amountIn);
        assertGt(WBTC.balanceOf(address(levvaVault)), 0);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactInputV4AllExcept() public {
        deal(address(USDC), address(levvaVault), 105_000 * 10 ** 6);
        uint128 except = 100_000 * 10 ** 6;

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(address(WBTC)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)),
            hookData: ""
        });

        IV4Router.ExactInputParams memory params = IV4Router.ExactInputParams({
            path: path,
            currencyIn: Currency.wrap(address(USDC)),
            amountIn: except,
            amountOutMinimum: 0
        });

        vm.prank(address(levvaVault));
        adapter.swapExactInputV4AllExcept(params, block.timestamp);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(levvaVault));
        assertEq(usdcBalanceAfter, except);
        assertGt(WBTC.balanceOf(address(levvaVault)), 0);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactOutputV4() public {
        uint128 amountOut = 10 ** 8;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(address(USDC)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)),
            hookData: ""
        });

        IV4Router.ExactOutputParams memory params = IV4Router.ExactOutputParams({
            path: path,
            currencyOut: Currency.wrap(address(WBTC)),
            amountOut: amountOut,
            amountInMaximum: uint128(usdcBalanceBefore)
        });

        vm.prank(address(levvaVault));
        adapter.swapExactOutputV4(params, block.timestamp);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(levvaVault));
        assertGt(usdcBalanceBefore, usdcBalanceAfter);
        assertNotEq(usdcBalanceAfter, 0);
        assertEq(WBTC.balanceOf(address(levvaVault)), amountOut);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }
}
