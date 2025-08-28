// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
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

        adapter = new OriginETHAdapter(address(WETH), address(OETH_VAULT), address(OETH), address(W_OETH));
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

    function testRequestWithdrawal() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 1 ether;
        vm.prank(address(levvaVault));
        uint256 wrappedOETHAmount = adapter.deposit(depositAmount, 0);

        vm.prank(address(levvaVault));
        (uint256 requestId, uint256 oETHAmount) = adapter.requestWithdrawal(wrappedOETHAmount);

        // IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
        // assertEq(requestId, nft.nextRequestId() - 1);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), 0);
        assertEq(W_OETH.balanceOf(address(levvaVault)), 0);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(OETH.balanceOf(address(adapter)), 0);
        assertEq(W_OETH.balanceOf(address(adapter)), 0);

        // vm.prank(address(levvaVault));
        // (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        // assertEq(assets.length, 1);
        // assertEq(amounts.length, 1);
        // assertEq(assets[0], address(WETH));
        // assertApproxEqAbs(amounts[0], depositAmount, 2);

        _assertNoDebtAssets();
    }

    function testRequestWithdrawalAllExcept() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
        uint256 depositAmount = 4 ether;
        vm.prank(address(levvaVault));
        uint256 wrappedOETHAmount = adapter.deposit(depositAmount, 0);

        uint256 except = 1 ether;
        vm.prank(address(levvaVault));
        (uint256 requestId, uint256 oETHAmount)  = adapter.requestWithdrawalAllExcept(except);

        // IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
        // assertEq(requestId, nft.nextRequestId() - 1);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(levvaVault)), depositAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), 0);
        assertEq(W_OETH.balanceOf(address(levvaVault)), except);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(OETH.balanceOf(address(adapter)), 0);
        assertEq(W_OETH.balanceOf(address(adapter)), 0);

        // vm.prank(address(levvaVault));
        // (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        // assertEq(assets.length, 1);
        // assertEq(amounts.length, 1);
        // assertEq(assets[0], address(WETH));
        // assertApproxEqAbs(amounts[0], IweETH(address(WEETH)).getEETHByWeETH(weethAmount - except), 2);

        _assertNoDebtAssets();
    }

    // function testClaimWithdrawEth() public {
    //     uint256 wethBalanceBefore = WETH.balanceOf(address(levvaVault));
    //     uint256 depositAmount = 1 ether;
    //     vm.prank(address(levvaVault));
    //     uint256 weethAmount = adapter.deposit(depositAmount);

    //     vm.prank(address(levvaVault));
    //     adapter.requestWithdraw(weethAmount);
    //     assert(!adapter.claimPossible(address(levvaVault)));

    //     IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
    //     uint256 lastRequest = nft.nextRequestId() - 1;
    //     vm.prank(ETHERFI_ADMIN);
    //     nft.finalizeRequests(lastRequest);

    //     assert(adapter.claimPossible(address(levvaVault)));

    //     vm.prank(address(levvaVault));
    //     adapter.claimWithdraw();

    //     assert(!adapter.claimPossible(address(levvaVault)));

    //     assertApproxEqAbs(WETH.balanceOf(address(levvaVault)), wethBalanceBefore, 2);
    //     assertEq(eETH.balanceOf(address(levvaVault)), 0);
    //     assertEq(WETH.balanceOf(address(adapter)), 0);
    //     assertEq(eETH.balanceOf(address(adapter)), 0);

    //     vm.prank(address(levvaVault));
    //     (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
    //     assertEq(assets.length, 1);
    //     assertEq(amounts.length, 1);
    //     assertEq(assets[0], address(WETH));
    //     assertEq(amounts[0], 0);

    //     (assets, amounts) = adapter.getManagedAssets(address(levvaVault));
    //     assertEq(assets.length, 1);
    //     assertEq(amounts.length, 1);
    //     assertEq(assets[0], address(WETH));
    //     assertEq(amounts[0], 0);

    //     _assertNoDebtAssets();
    // }

    // function testClaimWithdrawEthNotFinalized() public {
    //     uint256 depositAmount = 1 ether;
    //     vm.prank(address(levvaVault));
    //     uint256 weethAmount = adapter.deposit(depositAmount);

    //     vm.prank(address(levvaVault));
    //     adapter.requestWithdraw(weethAmount);

    //     vm.prank(address(levvaVault));
    //     vm.expectRevert("Request is not finalized");
    //     adapter.claimWithdraw();
    // }

    function testClaimNoRequests() public {
        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(OriginETHAdapter.NoWithdrawRequestInQueue.selector));
        adapter.claimWithdrawal();
    }

    function _assertNoDebtAssets() private {
        vm.prank(address(levvaVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }
}
