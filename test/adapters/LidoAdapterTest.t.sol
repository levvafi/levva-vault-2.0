// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {LidoAdapter} from "../../contracts/adapters/lido/LidoAdapter.sol";
import {ILidoWithdrawalQueue} from "../../contracts/adapters/lido/interfaces/ILidoWithdrawalQueue.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";
import {IWstETH} from "../../contracts/adapters/lido/interfaces/IWstETH.sol";

contract LidoAdapterTest is Test {
    uint256 public constant FORK_BLOCK = 22567800;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    ILidoWithdrawalQueue private constant LidoWithdrawalQueue =
        ILidoWithdrawalQueue(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

    LidoAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(WETH), address(USDC));
        oracle.setPrice(oracle.ONE(), address(WSTETH), address(USDC));

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

        adapter = new LidoAdapter(address(WETH), address(WSTETH), address(LidoWithdrawalQueue));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 1);

        levvaVault.addTrackedAsset(address(WETH));
        levvaVault.addTrackedAsset(address(WSTETH));
    }

    function test_constructor() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LidoAdapter(address(0), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LidoAdapter(address(WETH), address(0), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new LidoAdapter(address(WETH), address(WSTETH), address(0));

        LidoAdapter _adapter = new LidoAdapter(address(WETH), address(WSTETH), address(LidoWithdrawalQueue));
        assertEq(address(_adapter.getWETH()), address(WETH));
        assertEq(address(_adapter.getWstETH()), address(WSTETH));
        assertEq(address(_adapter.getLidoWithdrawalQueue()), address(LidoWithdrawalQueue));
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IExternalPositionAdapter).interfaceId));
    }

    function test_stake() public {
        uint256 amount = 5 ether;

        deal(address(WETH), address(levvaVault), amount);
        vm.prank(address(levvaVault));
        adapter.stake(amount);

        assertTrue(WSTETH.balanceOf(address(levvaVault)) > 0);
        assertEq(WETH.balanceOf(address(levvaVault)), 0);
        assertEq(WSTETH.balanceOf(address(adapter)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function test_stakeAllExcept() public {
        uint256 except = 5 ether;
        uint256 initialAmount = 7 ether;
        uint256 amount = initialAmount - except;

        deal(address(WETH), address(levvaVault), initialAmount);
        vm.prank(address(levvaVault));
        adapter.stakeAllExcept(except);

        uint256 wstETHBalance = WSTETH.balanceOf(address(levvaVault));
        assertApproxEqAbs(IWstETH(address(WSTETH)).getStETHByWstETH(wstETHBalance), amount, 2);
        assertEq(WETH.balanceOf(address(levvaVault)), except);
        assertEq(WSTETH.balanceOf(address(adapter)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function test_stakeShouldFailWhenTransferValueFails() public {
        uint256 amount = 5 ether;

        deal(address(WETH), address(levvaVault), amount);
        vm.prank(address(levvaVault));
        bytes memory data;
        vm.mockCallRevert(address(WSTETH), data, data);
        vm.expectRevert(abi.encodeWithSelector(LidoAdapter.LidoAdapter__StakeFailed.selector));
        adapter.stake(amount);
    }

    function test_requestWithdrawal() public {
        uint256 amount = 5 ether;
        deal(address(WETH), address(levvaVault), amount);
        vm.startPrank(address(levvaVault));
        adapter.stake(amount);

        uint256 expectedRequestId = LidoWithdrawalQueue.getLastRequestId() + 1;
        uint256 withdrawalAmount = 2 ether;
        uint256 withdrawalStEthAmount = IWstETH(address(WSTETH)).getStETHByWstETH(withdrawalAmount);
        vm.expectEmit(true, true, false, false);
        emit LidoAdapter.WithdrawalRequested(expectedRequestId, withdrawalAmount);
        adapter.requestWithdrawal(withdrawalAmount);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts.length, 1);
        assertApproxEqAbs(amounts[0], withdrawalStEthAmount, 1);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);

        assertEq(adapter.getWithdrawalQueueStart(address(levvaVault)), 0);
        assertEq(adapter.getWithdrawalQueueEnd(address(levvaVault)), 1);
        assertEq(adapter.getWithdrawalQueueRequest(address(levvaVault), 0), LidoWithdrawalQueue.getLastRequestId());
    }

    function test_requestWithdrawalAllExcept() public {
        uint256 amount = 5 ether;
        deal(address(WETH), address(levvaVault), amount);
        vm.startPrank(address(levvaVault));
        adapter.stake(amount);

        uint256 wstETHBalance = WSTETH.balanceOf(address(levvaVault));

        uint256 expectedRequestId = LidoWithdrawalQueue.getLastRequestId() + 1;
        uint256 exceptAmount = 3 ether;
        uint256 withdrawalAmount = wstETHBalance - exceptAmount;

        uint256 withdrawalStEthAmount = IWstETH(address(WSTETH)).getStETHByWstETH(withdrawalAmount);
        vm.expectEmit(true, true, false, false);
        emit LidoAdapter.WithdrawalRequested(expectedRequestId, withdrawalAmount);
        adapter.requestWithdrawalAllExcept(exceptAmount);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts.length, 1);
        assertApproxEqAbs(amounts[0], withdrawalStEthAmount, 1);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);

        assertEq(adapter.getWithdrawalQueueStart(address(levvaVault)), 0);
        assertEq(adapter.getWithdrawalQueueEnd(address(levvaVault)), 1);
        assertEq(adapter.getWithdrawalQueueRequest(address(levvaVault), 0), LidoWithdrawalQueue.getLastRequestId());
    }

    function test_requestWithdrawalMoreThanMaxWithdrawal() public {
        uint256 amount = 5000 ether;
        deal(address(WETH), address(levvaVault), amount);
        vm.startPrank(address(levvaVault));
        adapter.stake(amount);

        uint256 withdrawalAmount = 2500 ether;
        uint256 withdrawalStEthAmount = IWstETH(address(WSTETH)).getStETHByWstETH(withdrawalAmount);
        uint256 lastRequestId = LidoWithdrawalQueue.getLastRequestId();
        vm.expectEmit(true, false, false, false);
        emit LidoAdapter.WithdrawalRequested(lastRequestId + 1, withdrawalAmount);

        vm.expectEmit(true, false, false, false);
        emit LidoAdapter.WithdrawalRequested(lastRequestId + 2, withdrawalAmount);

        adapter.requestWithdrawal(withdrawalAmount);

        assertEq(adapter.getWithdrawalQueueStart(address(levvaVault)), 0);
        assertEq(adapter.getWithdrawalQueueEnd(address(levvaVault)), 4);
        assertEq(adapter.getWithdrawalQueueRequest(address(levvaVault), 0), lastRequestId + 1);
        assertEq(adapter.getWithdrawalQueueRequest(address(levvaVault), 1), lastRequestId + 2);
        assertEq(adapter.getWithdrawalQueueRequest(address(levvaVault), 2), lastRequestId + 3);
        assertEq(adapter.getWithdrawalQueueRequest(address(levvaVault), 3), lastRequestId + 4);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts.length, 1);
        assertApproxEqAbs(amounts[0], withdrawalStEthAmount, 10);
    }

    function test_claimWithdrawal1() public {
        assertFalse(adapter.isClaimable(address(levvaVault)));

        uint256 amount = 5 ether;
        deal(address(WETH), address(levvaVault), amount);
        vm.startPrank(address(levvaVault));
        adapter.stake(amount);
        uint256 withdrawalAmount = 2 ether;
        adapter.requestWithdrawal(withdrawalAmount);
        vm.stopPrank();

        assertFalse(adapter.isClaimable(address(levvaVault)));

        _finalizeWithdrawalRequests();

        assertTrue(adapter.isClaimable(address(levvaVault)));

        uint256 balanceBefore = WETH.balanceOf(address(levvaVault));

        vm.expectEmit(true, true, false, false);
        emit LidoAdapter.WithdrawalClaimed(LidoWithdrawalQueue.getLastRequestId(), withdrawalAmount);
        vm.prank(address(levvaVault));
        adapter.claimWithdrawal();

        assertTrue(WETH.balanceOf(address(levvaVault)) > balanceBefore);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function test_claimWithdrawalShouldFailWhenQueueIsEmpty() public {
        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(LidoAdapter.LidoAdapter__NoWithdrawRequestInQueue.selector));
        adapter.claimWithdrawal();
    }

    function test_getDebtAssets() public view {
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function test_getManagedAssets() public {
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        uint256 amount = 5 ether;
        deal(address(WETH), address(levvaVault), amount);
        vm.startPrank(address(levvaVault));
        adapter.stake(amount);
        uint256 withdrawalAmount = 2 ether;
        adapter.requestWithdrawal(withdrawalAmount);

        (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
    }

    function test_getWithdrawalQueueRequestShouldFailWhenEmptyQueue() public {
        vm.expectRevert(abi.encodeWithSelector(LidoAdapter.LidoAdapter__NoWithdrawRequestInQueue.selector));
        adapter.getWithdrawalQueueRequest(address(levvaVault), 0);
    }

    function test_receive() public {
        address user = address(0x123);
        uint256 amount = 1 ether;
        vm.deal(user, amount);
        vm.startPrank(user);
        (bool success,) = address(adapter).call{value: amount}("");
        assertTrue(success);
    }

    function test_getWithdrawalQueueRequest() public {}

    function test_getWithdrawalQueueStart() public {}

    function test_getWithdrawalQueueEnd() public {}

    function _finalizeWithdrawalRequests() internal {
        address finalizer = LidoWithdrawalQueue.getRoleMember(LidoWithdrawalQueue.FINALIZE_ROLE(), 0);
        uint256 ethersToFinalize = LidoWithdrawalQueue.unfinalizedStETH();
        vm.deal(finalizer, ethersToFinalize);

        uint256 lastRequestId = LidoWithdrawalQueue.getLastRequestId();
        uint256 maxShares = 10 ** 27;
        vm.prank(finalizer);
        LidoWithdrawalQueue.finalize{value: ethersToFinalize}(lastRequestId, maxShares);
    }
}
