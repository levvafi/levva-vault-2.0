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
import {AutoUSDAdapter} from "../../contracts/adapters/tokemak/AutoUSDAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract AutoETHAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC4626 private constant AUTO_ETH = IERC4626(0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56);
    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    AutoUSDAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(95, 100), address(AUTO_ETH), address(WETH));

        address levvaVaultImplementation = address(new LevvaVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address levvaVaultFactoryImplementation = address(new LevvaVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            LevvaVaultFactory.initialize.selector, levvaVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy levvaVaultFactoryProxy = new ERC1967Proxy(levvaVaultFactoryImplementation, data);
        LevvaVaultFactory levvaVaultFactory = LevvaVaultFactory(address(levvaVaultFactoryProxy));

        (address deployedVault,) = levvaVaultFactory.deployVault(
            address(WETH),
            "lpName",
            "lpSymbol",
            "withdrawalQueueName",
            "withdrawalQueueSymbol",
            address(0xFEE),
            address(oracle)
        );

        levvaVault = LevvaVault(deployedVault);
        levvaVault.setMaxTrackedAssets(type(uint8).max);

        adapter = new AutoUSDAdapter(address(AUTO_ETH));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(WETH), address(levvaVault), 10 ** 24);

        levvaVault.addTrackedAsset(address(AUTO_ETH));
    }

    function testSetup() public view {
        assertEq(adapter.autoUSD(), address(AUTO_ETH));
        assertEq(adapter.USDC(), address(WETH));
    }

    function testDeposit() public {
        uint256 usdcBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 10 ** 18;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(usdcBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertEq(AUTO_ETH.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(AUTO_ETH.balanceOf(address(adapter)), 0);
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 10 ** 18;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        uint256 expectedUsdc = adapter.redeem(expectedLpTokens);

        assertEq(WETH.balanceOf(address(levvaVault)), usdeBalanceBefore - depositAmount + expectedUsdc);
        assertEq(AUTO_ETH.balanceOf(address(levvaVault)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(AUTO_ETH.balanceOf(address(adapter)), 0);
    }
}
