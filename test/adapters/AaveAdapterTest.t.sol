// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {AaveAdapter} from "../../contracts/adapters/aave/AaveAdapter.sol";
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
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        aUsdc = IERC20(IPool(AAVE_POOL_PROVIDER.getPool()).getReserveData(address(USDC)).aTokenAddress);
        aUsdt = IERC20(IPool(AAVE_POOL_PROVIDER.getPool()).getReserveData(address(USDT)).aTokenAddress);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDT), address(USDC));
        oracle.setPrice(oracle.ONE(), address(aUsdc), address(USDC));
        oracle.setPrice(oracle.ONE(), address(aUsdt), address(USDC));

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

        adapter = new AaveAdapter(address(AAVE_POOL_PROVIDER));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDC), address(levvaVault), 10 ** 12);
        deal(address(USDT), address(levvaVault), 10 ** 12);

        levvaVault.addTrackedAsset(address(USDT));
        levvaVault.addTrackedAsset(address(aUsdc));
    }

    function testSupply() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        adapter.supply(address(USDC), supplyAmount);

        assertEq(usdcBalanceBefore - USDC.balanceOf(address(levvaVault)), supplyAmount);
        assertApproxEqAbs(aUsdc.balanceOf(address(levvaVault)), supplyAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSupplyAllExcept() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 exceptAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        adapter.supplyAllExcept(address(USDC), exceptAmount);

        assertEq(USDC.balanceOf(address(levvaVault)), exceptAmount);
        assertApproxEqAbs(aUsdc.balanceOf(address(levvaVault)), usdcBalanceBefore - exceptAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testFullWithdraw() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        adapter.supply(address(USDC), supplyAmount);

        vm.prank(address(levvaVault));
        adapter.withdraw(address(USDC), type(uint256).max);

        assertApproxEqAbs(usdcBalanceBefore, USDC.balanceOf(address(levvaVault)), 1);
        assertEq(aUsdc.balanceOf(address(levvaVault)), 0);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testPartialWithdraw() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        adapter.supply(address(USDC), supplyAmount);

        uint256 aTokenBalanceBefore = aUsdc.balanceOf(address(levvaVault));
        uint256 withdrawalAmount = aTokenBalanceBefore / 2;
        vm.prank(address(levvaVault));
        adapter.withdraw(address(USDC), withdrawalAmount);

        assertApproxEqAbs(
            usdcBalanceBefore - (aTokenBalanceBefore - withdrawalAmount), USDC.balanceOf(address(levvaVault)), 1
        );
        assertApproxEqAbs(aUsdc.balanceOf(address(levvaVault)), aTokenBalanceBefore - withdrawalAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testWithdrawAllExcept() public {
        uint256 usdcBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 supplyAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        adapter.supply(address(USDC), supplyAmount);

        vm.prank(address(levvaVault));
        uint256 exceptAmount = 10 * 10 ** 6;
        adapter.withdrawAllExcept(address(USDC), exceptAmount);

        assertApproxEqAbs(usdcBalanceBefore, USDC.balanceOf(address(levvaVault)) + exceptAmount, 1);
        assertApproxEqAbs(aUsdc.balanceOf(address(levvaVault)), exceptAmount, 1);
        assertEq(aUsdc.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }
}
