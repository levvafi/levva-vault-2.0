// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {AaveAdapter} from "../../contracts/adapters/aave/AaveAdapter.sol";
import {AbstractUniswapV3Adapter} from "../../contracts/adapters/uniswap/AbstractUniswapV3Adapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract AaveAdapterTest is Test {
    uint256 public constant FORK_BLOCK = 22515980;

    IPoolAddressesProvider private constant AAVE_POOL_PROVIDER =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private aToken;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    AaveAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        aToken = IERC20(IPool(AAVE_POOL_PROVIDER.getPool()).getReserveData(address(USDC)).aTokenAddress);

        EulerRouterMock oracle = new EulerRouterMock();

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, USDC, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new AaveAdapter(address(AAVE_POOL_PROVIDER));
        levvaVault.addAdapter(address(adapter));
        assertNotEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDC), address(levvaVault), 10 ** 18);
    }

    function testSupply() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        adapter.supply(address(USDC), supplyAmount);

        assertEq(usdcBalanceBefore - USDC.balanceOf(address(levvaVault)), supplyAmount);
        assertApproxEqAbs(aToken.balanceOf(address(levvaVault)), supplyAmount, 1);
        assertEq(aToken.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(aToken));
        assertEq(amounts[0], aToken.balanceOf(address(levvaVault)));

        (assets, amounts) = adapter.getVaultManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(aToken));
        assertEq(amounts[0], aToken.balanceOf(address(levvaVault)));
    }

    function testFullWithdraw() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        adapter.supply(address(USDC), supplyAmount);

        vm.prank(address(levvaVault));
        adapter.withdraw(address(USDC), type(uint256).max);

        assertApproxEqAbs(usdcBalanceBefore, USDC.balanceOf(address(levvaVault)), 1);
        assertEq(aToken.balanceOf(address(levvaVault)), 0);
        assertEq(aToken.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (assets, amounts) = adapter.getVaultManagedAssets(address(levvaVault));
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function testPartialWithdraw() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        adapter.supply(address(USDC), supplyAmount);

        uint256 aTokenBalanceBefore = aToken.balanceOf(address(levvaVault));
        uint256 withdrawalAmount = aTokenBalanceBefore / 2;
        vm.prank(address(levvaVault));
        adapter.withdraw(address(USDC), withdrawalAmount);

        assertApproxEqAbs(
            usdcBalanceBefore - (aTokenBalanceBefore - withdrawalAmount), USDC.balanceOf(address(levvaVault)), 1
        );
        assertApproxEqAbs(aToken.balanceOf(address(levvaVault)), aTokenBalanceBefore - withdrawalAmount, 1);
        assertEq(aToken.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(aToken));
        assertEq(amounts[0], aToken.balanceOf(address(levvaVault)));

        (assets, amounts) = adapter.getVaultManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(aToken));
        assertEq(amounts[0], aToken.balanceOf(address(levvaVault)));
    }
}
