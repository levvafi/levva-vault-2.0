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
import {ResolvAdapter} from "../../contracts/adapters/resolv/ResolvAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract ResolvAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC4626 private constant WSTUSR = IERC4626(0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055);
    IERC20 private constant USR = IERC20(0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110);

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    ResolvAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USR), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(95, 100), address(WSTUSR), address(USDC));

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

        adapter = new ResolvAdapter(address(WSTUSR));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USR), address(levvaVault), 10 ** 24);

        levvaVault.addTrackedAsset(address(USR));
        levvaVault.addTrackedAsset(address(WSTUSR));
    }

    function testSetup() public view {
        assertEq(adapter.wstUSR(), address(WSTUSR));
        assertEq(adapter.USR(), address(USR));
    }

    function testDeposit() public {
        uint256 usrBalanceBefore = USR.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(usrBalanceBefore - USR.balanceOf(address(levvaVault)), depositAmount);
        assertEq(WSTUSR.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(USR.balanceOf(address(adapter)), 0);
        assertEq(WSTUSR.balanceOf(address(adapter)), 0);
    }

    function testDepositNotTrackedAsset() public {
        levvaVault.removeTrackedAsset(address(WSTUSR));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, WSTUSR));
        adapter.deposit(1000 * 10 ** 18);
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = USR.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.redeem(expectedLpTokens);

        assertApproxEqAbs(USR.balanceOf(address(levvaVault)), usdeBalanceBefore, 1);
        assertEq(WSTUSR.balanceOf(address(levvaVault)), 0);
        assertEq(USR.balanceOf(address(adapter)), 0);
        assertEq(WSTUSR.balanceOf(address(adapter)), 0);
    }

    function testRedeemNotTrackedAsset() public {
        uint256 depositAmount = USR.balanceOf(address(levvaVault));
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        levvaVault.removeTrackedAsset(address(USR));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, USR));
        adapter.redeem(expectedLpTokens);
    }
}
