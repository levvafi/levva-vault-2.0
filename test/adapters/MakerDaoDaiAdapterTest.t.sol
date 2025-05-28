// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {MakerDaoDaiAdapter} from "../../contracts/adapters/makerDao/MakerDaoDaiAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract MakerDaoDaiAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC4626 private constant S_DAI = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    MakerDaoDaiAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(DAI), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(95, 100), address(S_DAI), address(USDC));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, USDC, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new MakerDaoDaiAdapter(address(S_DAI));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(DAI), address(levvaVault), 10 ** 24);

        levvaVault.addTrackedAsset(address(DAI));
        levvaVault.addTrackedAsset(address(S_DAI));
    }

    function testSetup() public view {
        assertEq(adapter.sDAI(), address(S_DAI));
        assertEq(adapter.DAI(), address(DAI));
    }

    function testDeposit() public {
        uint256 balanceBefore = DAI.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(balanceBefore - DAI.balanceOf(address(levvaVault)), depositAmount);
        assertEq(S_DAI.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(DAI.balanceOf(address(adapter)), 0);
        assertEq(S_DAI.balanceOf(address(adapter)), 0);
    }

    function testDepositNotTrackedAsset() public {
        levvaVault.removeTrackedAsset(address(S_DAI));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, S_DAI));
        adapter.deposit(1000 * 10 ** 18);
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = DAI.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.redeem(expectedLpTokens);

        assertApproxEqAbs(DAI.balanceOf(address(levvaVault)), usdeBalanceBefore, 1);
        assertEq(S_DAI.balanceOf(address(levvaVault)), 0);
        assertEq(DAI.balanceOf(address(adapter)), 0);
        assertEq(S_DAI.balanceOf(address(adapter)), 0);
    }

    function testRedeemNotTrackedAsset() public {
        uint256 depositAmount = DAI.balanceOf(address(levvaVault));
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        levvaVault.removeTrackedAsset(address(DAI));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, DAI));
        adapter.redeem(expectedLpTokens);
    }
}
