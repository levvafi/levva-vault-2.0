// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {OriginETHAdapter} from "../../contracts/adapters/origin/OriginETHAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {IOETHVault} from "../../contracts/adapters/origin/interfaces/IOETHVault.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract OriginETHAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IOETHVault private constant OETH_VAULT = IOETHVault(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);
    IERC20 private constant OETH = IERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);
    IERC20 private constant W_OETH = IERC20(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    OriginETHAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(11, 10), address(W_OETH), address(WETH));

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
        levvaVault.setMaxExternalPositionAdapters(type(uint8).max);
        levvaVault.setMaxTrackedAssets(type(uint8).max);

        adapter = new OriginETHAdapter(address(W_OETH));
        levvaVault.addAdapter(address(adapter));
        assertNotEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(WETH), address(levvaVault), 10 ether);

        levvaVault.addTrackedAsset(address(W_OETH));
    }

    function testInit() public view {
        assertEq(address(adapter.weth()), address(WETH));
        assertEq(address(adapter.oETHVault()), address(OETH_VAULT));
        assertEq(address(adapter.oETH()), address(OETH));
        assertEq(address(adapter.wrappedOETH()), address(W_OETH));
    }

    function testAddressZeroRevert() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        new OriginETHAdapter(address(0));
    }

    function testDeposit() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));

        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        uint256 wOETHAmount = adapter.deposit(depositAmount, 0);

        assertEq(WETH.balanceOf(address(levvaVault)), wethBalanceBefore - depositAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), 0);
        assertEq(W_OETH.balanceOf(address(levvaVault)), wOETHAmount);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(OETH.balanceOf(address(adapter)), 0);
        assertEq(W_OETH.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        _assertNoDebtAssets();
    }

    function testDepositLessThanMinAmount() public {
        uint256 depositAmount = 1 ether;
        vm.expectRevert(abi.encodeWithSelector(OriginETHAdapter.LessThanMinAmount.selector));
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount, type(uint256).max);
    }

    function testDepositAllExcept() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));

        uint256 except = 2 ether;
        uint256 depositAmount = wethBalanceBefore - except;
        vm.prank(address(levvaVault));
        uint256 wOETHAmount = adapter.depositAllExcept(except, 0);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), 0);
        assertEq(W_OETH.balanceOf(address(levvaVault)), wOETHAmount);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(OETH.balanceOf(address(adapter)), 0);
        assertEq(W_OETH.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        _assertNoDebtAssets();
    }

    function testDepositAllExceptLessThanMinAmount() public {
        vm.expectRevert(abi.encodeWithSelector(OriginETHAdapter.LessThanMinAmount.selector));
        vm.prank(address(levvaVault));
        adapter.depositAllExcept(0, type(uint256).max);
    }

    function testRequestWithdrawal() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        uint256 wrappedOETHAmount = adapter.deposit(depositAmount, 0);

        vm.prank(address(levvaVault));
        (uint256 requestId, uint256 oETHAmount) = adapter.requestWithdrawal(wrappedOETHAmount);

        (,,, uint256 nextWithdrawalId) = OETH_VAULT.withdrawalQueueMetadata();
        assertEq(requestId, nextWithdrawalId - 1);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), 0);
        assertEq(W_OETH.balanceOf(address(levvaVault)), 0);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(OETH.balanceOf(address(adapter)), 0);
        assertEq(W_OETH.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], oETHAmount);

        _assertNoDebtAssets();
    }

    function testRequestWithdrawalAllExcept() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 4 ether;
        vm.prank(address(levvaVault));
        adapter.deposit(depositAmount, 0);

        uint256 except = 1 ether;
        vm.prank(address(levvaVault));
        (uint256 requestId, uint256 oETHAmount) = adapter.requestWithdrawalAllExcept(except);

        (,,, uint256 nextWithdrawalId) = OETH_VAULT.withdrawalQueueMetadata();
        assertEq(requestId, nextWithdrawalId - 1);

        assertEq(WETH.balanceOf(address(levvaVault)), wethBalanceBefore - depositAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), 0);
        assertEq(W_OETH.balanceOf(address(levvaVault)), except);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(OETH.balanceOf(address(adapter)), 0);
        assertEq(W_OETH.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], oETHAmount);

        _assertNoDebtAssets();
    }

    function testClaimWithdrawal() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        uint256 wrappedOETHAmount = adapter.deposit(depositAmount, 0);

        vm.prank(address(levvaVault));
        (, uint256 oETHAmount) = adapter.requestWithdrawal(wrappedOETHAmount);

        (address token, uint256 claimableAmount) = adapter.claimable(address(levvaVault));
        assertEq(token, address(0));
        assertEq(claimableAmount, 0);

        skip(OETH_VAULT.withdrawalClaimDelay());

        vm.expectRevert("Queue pending liquidity");
        vm.prank(address(levvaVault));
        adapter.claimWithdrawal();
    
        (token, claimableAmount) = adapter.claimable(address(levvaVault));
        assertEq(token, address(0));
        assertEq(claimableAmount, 0);

        _dealWethForClaim();
        
        (token, claimableAmount) = adapter.claimable(address(levvaVault));
        assertEq(token, address(WETH));
        assertEq(claimableAmount, oETHAmount);

        vm.prank(address(levvaVault));
        adapter.claimWithdrawal();

        (token, claimableAmount) = adapter.claimable(address(levvaVault));
        assertEq(token, address(0));
        assertEq(claimableAmount, 0);

        assertEq(WETH.balanceOf(address(levvaVault)), wethBalanceBefore - depositAmount + oETHAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), 0);
        assertEq(W_OETH.balanceOf(address(levvaVault)), 0);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(OETH.balanceOf(address(adapter)), 0);
        assertEq(W_OETH.balanceOf(address(adapter)), 0);

        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        _assertNoDebtAssets();
    }

    function testClaimNoRequests() public {
        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(OriginETHAdapter.NoWithdrawRequestInQueue.selector));
        adapter.claimWithdrawal();
    }

    function testUnwrap() public {
        uint256 oEthBalanceBefore = OETH.balanceOf(address(levvaVault));
        uint256 unwrapAmount = 1 ether;

        deal(address(W_OETH), address(levvaVault), unwrapAmount);

        vm.prank(address(levvaVault));
        uint256 oETHAmount = adapter.unwrap(unwrapAmount);

        assertEq(W_OETH.balanceOf(address(levvaVault)), 0);
        assertEq(OETH.balanceOf(address(levvaVault)), oEthBalanceBefore + oETHAmount);
    }

    function testUnwrapAllExcept() public {
        uint256 oEthBalanceBefore = OETH.balanceOf(address(levvaVault));
        
        uint256 unwrapExceptAmount = 1 ether;
        uint256 balance = 3 * unwrapExceptAmount / 2;
        deal(address(W_OETH), address(levvaVault), balance);

        vm.prank(address(levvaVault));
        uint256 oETHAmount = adapter.unwrapAllExcept(unwrapExceptAmount);

        assertEq(W_OETH.balanceOf(address(levvaVault)), unwrapExceptAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), oEthBalanceBefore + oETHAmount);
    }

    function _assertNoDebtAssets() private {
        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function _dealWethForClaim() private {
        (uint256 queued,, uint256 claimed,) = OETH_VAULT.withdrawalQueueMetadata();
        // Dealing weth to avoid this error:
        // https://github.com/OriginProtocol/origin-dollar/blob/a8be73bf0077a9d489a87ec9353280d1bbb59e3b/contracts/contracts/vault/OETHVaultCore.sol#L342
        // Math based on:
        // https://github.com/OriginProtocol/origin-dollar/blob/a8be73bf0077a9d489a87ec9353280d1bbb59e3b/contracts/contracts/vault/OETHVaultCore.sol#L393
        // request.queued = queue.claimable + addedClaimable => addedClaimable = request.queued - request.claimable
        // addedClaimable = min(queueShortfall, unallocatedWeth)
        // Our goal is to achieve 'queueShortfall = unallocatedWeth'
        // queueShortfall = queue.queued - queue.claimable
        // unallocatedWeth = wethBalance - allocatedWeth = wethBalance - (queue.claimable - queue.claimed)
        // queue.queued - queue.claimable = wethBalance - (queue.claimable - queue.claimed)
        // wethBalance = queue.queued - queue.claimed
        deal(address(WETH), address(OETH_VAULT), queued - claimed);
    }
}
