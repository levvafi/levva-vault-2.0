// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {SparkUSDCAdapter} from "../../contracts/adapters/spark/SparkUSDCAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract SparkUSDCAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC4626 private constant SPARK_USDC = IERC4626(0xBc65ad17c5C0a2A4D159fa5a503f4992c7B545FE);

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    SparkUSDCAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(95, 100), address(SPARK_USDC), address(USDC));

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

        adapter = new SparkUSDCAdapter(address(SPARK_USDC));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDC), address(levvaVault), 10 ** 24);

        levvaVault.addTrackedAsset(address(SPARK_USDC));
    }

    function testSetup() public view {
        assertEq(adapter.sparkUSDC(), address(SPARK_USDC));
        assertEq(adapter.USDC(), address(USDC));
    }

    function testDeposit() public {
        uint256 balanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(balanceBefore - USDC.balanceOf(address(levvaVault)), depositAmount);
        assertEq(SPARK_USDC.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(SPARK_USDC.balanceOf(address(adapter)), 0);
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.redeem(expectedLpTokens);

        assertApproxEqAbs(USDC.balanceOf(address(levvaVault)), usdeBalanceBefore, 1);
        assertEq(SPARK_USDC.balanceOf(address(levvaVault)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(SPARK_USDC.balanceOf(address(adapter)), 0);
    }
}
