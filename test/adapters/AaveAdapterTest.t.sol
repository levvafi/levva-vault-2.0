// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {AdapterActionExecutor} from "../../contracts/base/AdapterActionExecutor.sol";
import {AaveAdapter} from "../../contracts/adapters/aave/AaveAdapter.sol";
import {AbstractUniswapV3Adapter} from "../../contracts/adapters/uniswap/AbstractUniswapV3Adapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract AaveAdapterTest is Test {
    uint256 public constant FORK_BLOCK = 22515980;

    IPoolAddressesProvider private constant AAVE_POOL_PROVIDER =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private aUsdc;
    IERC20 private aUsdt;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    AaveAdapter private adapter;
    bytes4 private adapterId;
    LevvaVault private levvaVault;
    address vaultManager = makeAddr("VAULT_MANAGER");

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        aUsdc = IERC20(IPool(AAVE_POOL_PROVIDER.getPool()).getReserveData(address(USDC)).aTokenAddress);
        aUsdt = IERC20(IPool(AAVE_POOL_PROVIDER.getPool()).getReserveData(address(USDT)).aTokenAddress);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDT), address(USDC));
        oracle.setPrice(oracle.ONE(), address(aUsdc), address(USDC));
        oracle.setPrice(oracle.ONE(), address(aUsdt), address(USDC));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, USDC, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new AaveAdapter();
        adapterId = adapter.getAdapterId();
        levvaVault.addAdapter(
            address(adapter), abi.encodeWithSelector(AaveAdapter.initialize.selector, address(AAVE_POOL_PROVIDER))
        );
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDC), address(levvaVault), 10 ** 12);
        deal(address(USDT), address(levvaVault), 10 ** 12);

        levvaVault.addTrackedAsset(address(USDT));
        levvaVault.addTrackedAsset(address(aUsdc));

        levvaVault.addVaultManager(vaultManager, true);
        vm.deal(vaultManager, 1 ether);
    }

    function testSupply() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(vaultManager);
        _supply(address(USDC), supplyAmount);

        assertEq(usdcBalanceBefore - USDC.balanceOf(address(levvaVault)), supplyAmount);
        assertApproxEqAbs(aUsdc.balanceOf(address(levvaVault)), supplyAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSupplyNotTrackedAsset() public {
        uint256 supplyAmount = 1000 * 10 ** 6;

        vm.prank(vaultManager);
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, aUsdt));
        _supply(address(USDT), supplyAmount);
    }

    function testFullWithdraw() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.startPrank(vaultManager);
        _supply(address(USDC), supplyAmount);

        _withdraw(address(USDC), type(uint256).max);

        assertApproxEqAbs(usdcBalanceBefore, USDC.balanceOf(address(levvaVault)), 1);
        assertEq(aUsdc.balanceOf(address(levvaVault)), 0);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testPartialWithdraw() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.startPrank(vaultManager);
        _supply(address(USDC), supplyAmount);

        uint256 aTokenBalanceBefore = aUsdc.balanceOf(address(levvaVault));
        uint256 withdrawalAmount = aTokenBalanceBefore / 2;
        _withdraw(address(USDC), withdrawalAmount);

        assertApproxEqAbs(
            usdcBalanceBefore - (aTokenBalanceBefore - withdrawalAmount), USDC.balanceOf(address(levvaVault)), 1
        );
        assertApproxEqAbs(aUsdc.balanceOf(address(levvaVault)), aTokenBalanceBefore - withdrawalAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testWithdrawNotTrackedAsset() public {
        levvaVault.addTrackedAsset(address(aUsdt));

        uint256 supplyAmount = USDT.balanceOf(address(levvaVault));
        vm.prank(vaultManager);
        _supply(address(USDT), supplyAmount);

        levvaVault.removeTrackedAsset(address(USDT));

        vm.prank(vaultManager);
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, USDT));
        _withdraw(address(USDT), type(uint256).max);
    }

    function _supply(address asset, uint256 amount) private {
        AdapterActionExecutor.AdapterActionArg[] memory args = new LevvaVault.AdapterActionArg[](1);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: adapterId,
            data: abi.encodeWithSelector(AaveAdapter.supply.selector, asset, amount)
        });
        levvaVault.executeAdapterAction(args);
    }

    function _withdraw(address asset, uint256 amount) private {
        AdapterActionExecutor.AdapterActionArg[] memory args = new LevvaVault.AdapterActionArg[](1);
        args[0] = AdapterActionExecutor.AdapterActionArg({
            adapterId: adapterId,
            data: abi.encodeWithSelector(AaveAdapter.withdraw.selector, asset, amount)
        });
        levvaVault.executeAdapterAction(args);
    }
}
