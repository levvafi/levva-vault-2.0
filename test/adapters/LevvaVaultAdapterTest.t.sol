// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LevvaVaultAdapter} from "contracts/adapters/levvaVault/LevvaVaultAdapter.sol";
import {AdapterBase} from "contracts/adapters/AdapterBase.sol";
import {ILevvaPool} from "contracts/adapters/levvaPool/interfaces/ILevvaPool.sol";
import {FP96} from "contracts/adapters/levvaPool/FP96.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {IAdapter} from "contracts/interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "contracts/interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "contracts/libraries/Asserts.sol";
import {LevvaPoolMock} from "../mocks/LevvaPoolMock.t.sol";
import {IRequestWithdrawalVault} from "contracts/adapters/levvaVault/interfaces/IRequestWithdrawalVault.sol";
import {IWithdrawalQueue} from "contracts/adapters/levvaVault/interfaces/IWithdrawalQueue.sol";

contract LevvaVaultAdapterTest is Test {
    using FP96 for ILevvaPool.FixedPoint;
    using Math for uint256;

    uint256 private constant X96_ONE = 2 ** 96;
    uint256 private constant FORK_BLOCK_NUMBER = 22497400;

    IERC20 private WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    LevvaVaultAdapter internal adapter;

    LevvaVault internal vault;
    LevvaVault internal vault2;

    LevvaVault internal investVault1;
    LevvaVault internal investVault2;
    EulerRouterMock internal oracle;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK_NUMBER);
        vm.skip(block.chainid != 1, "Only mainnet fork test");

        oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(WETH), address(WETH));

        address levvaVaultImplementation = address(new LevvaVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address levvaVaultFactoryImplementation = address(new LevvaVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            LevvaVaultFactory.initialize.selector, levvaVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy levvaVaultFactoryProxy = new ERC1967Proxy(levvaVaultFactoryImplementation, data);
        LevvaVaultFactory levvaVaultFactory = LevvaVaultFactory(address(levvaVaultFactoryProxy));

        (address deployedVault,) =
            levvaVaultFactory.deployVault(address(WETH), "lpName", "lpSymbol", address(0xFEE), address(oracle));

        (address deployedVault2,) =
            levvaVaultFactory.deployVault(address(WETH), "lpName", "lpSymbol", address(0xFEE), address(oracle));

        vault = LevvaVault(deployedVault);
        vault2 = LevvaVault(deployedVault2);

        adapter = new LevvaVaultAdapter(address(levvaVaultFactoryProxy));
        vault.addAdapter(address(adapter));
        vault2.addAdapter(address(adapter));

        (deployedVault,) =
            levvaVaultFactory.deployVault(address(WETH), "lvvaWETH-1", "lvvaWETH-1", address(0xFEE), address(oracle));
        investVault1 = LevvaVault(deployedVault);

        (deployedVault,) =
            levvaVaultFactory.deployVault(address(WETH), "lvvaWETH-2", "lvvaWETH-2", address(0xFEE), address(oracle));
        investVault2 = LevvaVault(deployedVault);

        oracle.setPrice(oracle.ONE(), address(investVault1), address(WETH));
        oracle.setPrice(oracle.ONE(), address(investVault2), address(WETH));

        vault.addTrackedAsset(address(investVault1));
        vault.addTrackedAsset(address(investVault2));
        vault2.addTrackedAsset(address(investVault1));
        vault2.addTrackedAsset(address(investVault2));

        vm.deal(address(vault), 1 ether);
        deal(address(WETH), address(vault), 10 ether);

        vm.deal(address(vault2), 1 ether);
        deal(address(WETH), address(vault2), 10 ether);
    }

    function test_constructorShouldFailWhenZeroAddress() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LevvaVaultAdapter(address(0));
    }

    function test_deposit() public {
        uint256 depositAmount = 2 ether;
        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));

        vm.prank(address(vault));
        uint256 shares = adapter.deposit(address(investVault1), depositAmount);

        assertEq(investVault1.balanceOf(address(vault)), shares);
        assertEq(WETH.balanceOf(address(vault)), wethBalanceBefore - depositAmount);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(investVault1.balanceOf(address(adapter)), 0);

        _assertNoDebtAssets();
        _assertNoManagedAssets();
    }

    function test_depositAllExcept() public {
        uint256 except = 7 ether;

        vm.prank(address(vault));
        uint256 shares = adapter.depositAllExcept(address(investVault1), except);

        assertEq(investVault1.balanceOf(address(vault)), shares);
        assertEq(WETH.balanceOf(address(vault)), except);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(investVault1.balanceOf(address(adapter)), 0);
    }

    function test_depositShouldFailWhenWrongVaultAddress() public {
        uint256 depositAmount = 2 ether;

        vm.expectRevert(LevvaVaultAdapter.LevvaVaultAdapter__Forbidden.selector);
        vm.prank(address(vault));
        adapter.deposit(address(vault), depositAmount);
    }

    function test_depositShouldFailWhenNotLevvaVault() public {
        vm.expectRevert(LevvaVaultAdapter.LevvaVaultAdapter__UnknownVault.selector);
        hoax(address(vault));
        adapter.deposit(address(1), 0);
    }

    function test_requestRedeem() public {
        uint256 depositAmount = 2 ether;
        vm.startPrank(address(vault));
        uint256 shares = adapter.deposit(address(investVault1), depositAmount);

        uint256 redeemAmount = 1 ether;
        address withdrawalQueue = investVault1.withdrawalQueue();
        uint256 expectedRequestId = IWithdrawalQueue(withdrawalQueue).lastRequestId() + 1;

        vm.expectEmit(true, true, true, false);
        emit LevvaVaultAdapter.RequestWithdrawal(address(investVault1), expectedRequestId, redeemAmount);
        uint256 requestId = adapter.requestRedeem(address(investVault1), redeemAmount);

        assertEq(requestId, expectedRequestId);
        assertEq(investVault1.balanceOf(address(vault)), shares - redeemAmount);
        assertEq(IERC721(withdrawalQueue).ownerOf(requestId), address(adapter));

        assertFalse(adapter.claimPossible(address(investVault1), requestId));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(investVault1));
        assertEq(amounts.length, 1);
        assertEq(amounts[0], redeemAmount);

        _assertNoDebtAssets();
    }

    function test_reqeustRedeemManyRequests() public {
        uint256 depositAmount = 2 ether;
        vm.startPrank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);

        uint256 redeemAmount = 0.5 ether;
        address withdrawalQueue = investVault1.withdrawalQueue();

        uint256 requestId1 = adapter.requestRedeem(address(investVault1), redeemAmount);
        uint256 requestId2 = adapter.requestRedeem(address(investVault1), redeemAmount);

        assertEq(IERC721(withdrawalQueue).ownerOf(requestId1), address(adapter));
        assertEq(IERC721(withdrawalQueue).ownerOf(requestId2), address(adapter));
        assertEq(IERC721(withdrawalQueue).balanceOf(address(adapter)), 2);

        assertEq(adapter.claimPossible(address(investVault1), requestId1), false);
        assertEq(adapter.claimPossible(address(investVault1), requestId2), false);
    }

    function test_requestRedeemManyVaults() public {
        uint256 depositAmount1 = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount1);

        uint256 depositAmount2 = 4 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault2), depositAmount2);

        uint256 redeemAmount = 0.5 ether;
        address withdrawalQueue1 = investVault1.withdrawalQueue();
        address withdrawalQueue2 = investVault2.withdrawalQueue();

        vm.prank(address(vault));
        uint256 requestId1 = adapter.requestRedeem(address(investVault1), redeemAmount);
        vm.prank(address(vault));
        uint256 requestId2 = adapter.requestRedeem(address(investVault2), redeemAmount);

        assertEq(IERC721(withdrawalQueue1).ownerOf(requestId1), address(adapter));
        assertEq(IERC721(withdrawalQueue2).ownerOf(requestId2), address(adapter));
        assertEq(adapter.claimPossible(address(investVault1), requestId1), false);
        assertEq(adapter.claimPossible(address(investVault1), requestId2), false);

        _assertNoDebtAssets();
    }

    function test_requestRedeemAllExcept() public {
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        uint256 shares = adapter.deposit(address(investVault1), depositAmount);

        uint256 except = 0.5 ether;
        uint256 redeemAmount = shares - except;
        address withdrawalQueue = investVault1.withdrawalQueue();
        uint256 expectedRequestId = IWithdrawalQueue(withdrawalQueue).lastRequestId() + 1;

        vm.expectEmit(true, true, true, false);
        emit LevvaVaultAdapter.RequestWithdrawal(address(investVault1), expectedRequestId, redeemAmount);
        vm.prank(address(vault));
        uint256 requestId = adapter.requestRedeemAllExcept(address(investVault1), except);

        assertEq(requestId, expectedRequestId);
        assertEq(investVault1.balanceOf(address(vault)), except);
        _assertNoDebtAssets();
    }

    function test_requestRedeemShouldFailWhenNotVault() public {
        vm.expectRevert(LevvaVaultAdapter.LevvaVaultAdapter__UnknownVault.selector);
        hoax(address(vault));
        adapter.requestRedeem(address(1), 0);
    }

    function test_claimWithdrawalPartial() public {
        //deposit
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);

        //requestRedeem
        uint256 redeemAmount = 1 ether;
        address withdrawalQueue = investVault1.withdrawalQueue();

        vm.prank(address(vault));
        uint256 requestId = adapter.requestRedeem(address(investVault1), redeemAmount);

        _finalizeRequest(withdrawalQueue, requestId);
        assertTrue(adapter.claimPossible(address(investVault1), requestId));

        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));

        // claim
        vm.prank(address(vault));
        vm.expectEmit(true, true, true, false);
        emit LevvaVaultAdapter.ClaimWithdrawal(address(investVault1), requestId, redeemAmount);
        uint256 withdrawalAssets = adapter.claimWithdrawal(address(investVault1), requestId);

        assertEq(withdrawalAssets, redeemAmount);
        assertEq(WETH.balanceOf(address(vault)), wethBalanceBefore + withdrawalAssets);

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_claimWithdrawalFull() public {
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);

        uint256 redeemAmount = 2 ether;
        address withdrawalQueue = investVault1.withdrawalQueue();

        vm.prank(address(vault));
        uint256 requestId = adapter.requestRedeem(address(investVault1), redeemAmount);

        _finalizeRequest(withdrawalQueue, requestId);
        assertTrue(adapter.claimPossible(address(investVault1), requestId));

        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));

        vm.prank(address(vault));
        uint256 withdrawalAssets = adapter.claimWithdrawal(address(investVault1), requestId);
        assertEq(withdrawalAssets, depositAmount);
        assertEq(WETH.balanceOf(address(vault)), wethBalanceBefore + withdrawalAssets);
        assertFalse(adapter.claimPossible(address(investVault1), requestId));

        _assertNoManagedAssets();
        _assertNoDebtAssets();
    }

    function test_claimWithdrawFirstRequestFromTwo() public {
        //deposit
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);
        vm.prank(address(vault));
        adapter.deposit(address(investVault2), depositAmount);

        //request two redeems
        uint256 redeemAmount1 = depositAmount;
        uint256 redeemAmount2 = 0.7 ether;
        address withdrawalQueue1 = investVault1.withdrawalQueue();

        vm.prank(address(vault));
        uint256 requestId1 = adapter.requestRedeem(address(investVault1), redeemAmount1);

        vm.prank(address(vault));
        uint256 requestId2 = adapter.requestRedeem(address(investVault2), redeemAmount2);

        _finalizeRequest(withdrawalQueue1, requestId1);
        assertTrue(adapter.claimPossible(address(investVault1), requestId1));
        assertFalse(adapter.claimPossible(address(investVault2), requestId2));

        // claim first requestId
        vm.prank(address(vault));
        adapter.claimWithdrawal(address(investVault1), requestId1);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets(address(vault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(investVault2));
        assertEq(amounts[0], redeemAmount2);

        _assertNoDebtAssets();
    }

    function test_claimShouldFailWhenUnauthorized() public {
        // deposit
        uint256 depositAmount = 2 ether;
        vm.prank(address(vault));
        adapter.deposit(address(investVault1), depositAmount);

        uint256 depositAmount2 = 4 ether;
        vm.prank(address(vault2));
        adapter.deposit(address(investVault1), depositAmount2);

        // request redeem
        vm.prank(address(vault));
        uint256 requestId1 = adapter.requestRedeem(address(investVault1), depositAmount);

        vm.prank(address(vault2));
        uint256 requestId2 = adapter.requestRedeem(address(investVault1), depositAmount);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets(address(vault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(investVault1));
        assertEq(amounts[0], depositAmount);

        (assets, amounts) = adapter.getManagedAssets(address(vault2));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(investVault1));
        assertEq(amounts[0], depositAmount);

        _finalizeRequest(investVault1.withdrawalQueue(), requestId1);
        _finalizeRequest(investVault1.withdrawalQueue(), requestId2);

        //try to claim requestId1 by vault2
        vm.prank(address(vault2));
        vm.expectRevert(LevvaVaultAdapter.LevvaVaultAdapter__ClaimUnauthorized.selector);
        adapter.claimWithdrawal(address(investVault1), requestId1);
    }

    function test_claimWithdrawShouldFailWhenNotVault() public {
        vm.expectRevert(LevvaVaultAdapter.LevvaVaultAdapter__UnknownVault.selector);
        hoax(address(vault));
        adapter.claimWithdrawal(address(1), 0);
    }

    function _finalizeRequest(address withdrawalQueue, uint256 requestId) private {
        address finalizer = makeAddr("finalizer");
        IWithdrawalQueue(withdrawalQueue).addFinalizer(finalizer, true);
        vm.prank(finalizer);
        IWithdrawalQueue(withdrawalQueue).finalizeRequests(requestId);
    }

    function _assertNoDebtAssets() private view {
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function _assertNoManagedAssets() private view {
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }
}
