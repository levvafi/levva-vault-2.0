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
import {IUniversalRewardsDistributorBase} from
    "../../contracts/adapters/morpho/interfaces/IUniversalRewardsDistributorBase.sol";
import {MorphoAdapter} from "../../contracts/adapters/morpho/MorphoAdapter.sol";
import {MorphoAdapterV1_1} from "../../contracts/adapters/morpho/MorphoAdapterV1_1.sol";
import {MorphoAdapterBase} from "../../contracts/adapters/morpho/MorphoAdapterBase.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {MorphoRewardsDistributorMock} from "../mocks/MorphoRewardsDistributorMock.sol";

contract MorphoAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22579900;

    address private constant MORPHO_FACTORY = 0xA9c3D3a366466Fa809d1Ae982Fb2c46E5fC41101;
    address private constant MORPHO_FACTORY_V1_1 = 0x1897A8997241C1cD4bD0698647e4EB7213535c24;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant cbBTC = IERC20(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);

    IERC4626 private constant SteakhouseUSDC = IERC4626(0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB);
    IERC4626 private constant SparkDai = IERC4626(0x73e65DBD630f90604062f6E02fAb9138e713edD9);
    IERC4626 private constant cbBTCVault = IERC4626(0xb5e4576C2FAA16b0cC59D1A2f3366164844Ef9E0);

    IUniversalRewardsDistributorBase private rewardsDistributorMock;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    MorphoAdapter private adapter;
    MorphoAdapterV1_1 private adapterV1_1;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(DAI), address(USDC));
        oracle.setPrice(oracle.ONE(), address(SparkDai), address(USDC));
        oracle.setPrice(oracle.ONE(), address(SteakhouseUSDC), address(USDC));
        oracle.setPrice(oracle.ONE(), address(cbBTCVault), address(USDC));

        address levvaVaultImplementation = address(new LevvaVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address levvaVaultFactoryImplementation = address(new LevvaVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            LevvaVaultFactory.initialize.selector, levvaVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy levvaVaultFactoryProxy = new ERC1967Proxy(levvaVaultFactoryImplementation, data);
        LevvaVaultFactory levvaVaultFactory = LevvaVaultFactory(address(levvaVaultFactoryProxy));

        (address deployedVault,) =
            levvaVaultFactory.deployVault(address(USDC), "lpName", "lpSymbol", address(0xFEE), address(oracle));

        levvaVault = LevvaVault(deployedVault);

        adapter = new MorphoAdapter(MORPHO_FACTORY);
        adapterV1_1 = new MorphoAdapterV1_1(MORPHO_FACTORY_V1_1);

        levvaVault.addAdapter(address(adapter));
        levvaVault.addAdapter(address(adapterV1_1));

        deal(address(USDC), address(levvaVault), 10 ** 12);
        deal(address(cbBTC), address(levvaVault), 10 ** 10);

        levvaVault.addTrackedAsset(address(DAI));
        levvaVault.addTrackedAsset(address(SteakhouseUSDC));
        levvaVault.addTrackedAsset(address(SparkDai));
        levvaVault.addTrackedAsset(address(cbBTCVault));

        rewardsDistributorMock = IUniversalRewardsDistributorBase(address(new MorphoRewardsDistributorMock()));
        deal(address(USDC), address(rewardsDistributorMock), 10 ** 12);
    }

    function test_constructor() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new MorphoAdapter(address(0));
    }

    function test_getMetaMorphoFactory() public view {
        assertEq(adapter.getMetaMorphoFactory(), MORPHO_FACTORY);
        assertEq(adapterV1_1.getMetaMorphoFactory(), MORPHO_FACTORY_V1_1);
    }

    function test_deposit() public {
        uint256 balanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 depositAmount = 5000 * 10 ** 6;

        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(address(SteakhouseUSDC), depositAmount);

        assertEq(balanceBefore - USDC.balanceOf(address(levvaVault)), depositAmount);
        assertEq(SteakhouseUSDC.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(SteakhouseUSDC.balanceOf(address(adapter)), 0);
    }

    function test_depositAllExcept() public {
        uint256 except = 995_000 * 10 ** 6;

        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.depositAllExcept(address(SteakhouseUSDC), except);

        assertEq(USDC.balanceOf(address(levvaVault)), except);
        assertEq(SteakhouseUSDC.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(SteakhouseUSDC.balanceOf(address(adapter)), 0);
    }

    function test_depositV1_1() public {
        uint256 balanceBefore = cbBTC.balanceOf(address(levvaVault));
        uint256 depositAmount = 1 * 10 ** 8;

        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapterV1_1.deposit(address(cbBTCVault), depositAmount);

        assertEq(balanceBefore - cbBTC.balanceOf(address(levvaVault)), depositAmount);
        assertEq(cbBTCVault.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(cbBTC.balanceOf(address(adapter)), 0);
        assertEq(cbBTCVault.balanceOf(address(adapter)), 0);
    }

    function test_depositShouldFailWhenNotTrackedAsset() public {
        levvaVault.removeTrackedAsset(address(SteakhouseUSDC));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, SteakhouseUSDC));
        adapter.deposit(address(SteakhouseUSDC), 0);
    }

    function test_depositShouldFailWhenInvalidMorphoVault() public {
        vm.prank(address(levvaVault));
        vm.expectRevert(MorphoAdapterBase.MorphoAdapterBase__InvalidMorphoVault.selector);
        adapter.deposit(address(levvaVault), 1000 * 10 ** 18);
    }

    function test_redeem() public {
        deal(address(SteakhouseUSDC), address(levvaVault), 1000 * 10 ** 18);
        uint256 balanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 sharesToRedeem = 1000 * 10 ** 18;

        vm.prank(address(levvaVault));
        uint256 assets = adapter.redeem(address(SteakhouseUSDC), sharesToRedeem);

        assertTrue(assets > 0);
        assertEq(USDC.balanceOf(address(levvaVault)), balanceBefore + assets);
        assertEq(SteakhouseUSDC.balanceOf(address(levvaVault)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(SteakhouseUSDC.balanceOf(address(adapter)), 0);
    }

    function test_redeemAllExcept() public {
        deal(address(SteakhouseUSDC), address(levvaVault), 1000 * 10 ** 18);
        uint256 balanceBefore = USDC.balanceOf(address(levvaVault));
        uint256 except = 500 * 10 ** 18;
        //uint256 expectedToRedeem = SteakhouseUSDC.balanceOf(address(levvaVault)) - except;

        vm.prank(address(levvaVault));
        uint256 assets = adapter.redeemAllExcept(address(SteakhouseUSDC), except);

        assertTrue(assets > 0);
        assertEq(USDC.balanceOf(address(levvaVault)), balanceBefore + assets);
        assertEq(SteakhouseUSDC.balanceOf(address(levvaVault)), except);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(SteakhouseUSDC.balanceOf(address(adapter)), 0);
    }

    function test_redeemShouldFailWhenNotTrackedAsset() public {
        levvaVault.removeTrackedAsset(address(DAI));
        deal(address(SparkDai), address(levvaVault), 1000 * 10 ** 18);
        uint256 sharesToRedeem = 1000 * 10 ** 18;

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, DAI));
        adapter.redeem(address(SparkDai), sharesToRedeem);
    }

    function test_claimRewards() public {
        address rewardsAsset = address(USDC);
        uint256 claimable = 100 * 10 ** 6;
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(address(levvaVault));
        adapter.claimRewards(address(rewardsDistributorMock), rewardsAsset, claimable, proof);
    }

    function test_claimRewardsShouldFailWhenNotTrackedAsset() public {
        address rewardsAsset = address(1);
        uint256 claimable = 100 * 10 ** 6;
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, rewardsAsset));
        adapter.claimRewards(address(rewardsDistributorMock), rewardsAsset, claimable, proof);
    }
}
