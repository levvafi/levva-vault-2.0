// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {MakerDaoUsdsAdapter} from "../../contracts/adapters/makerDao/MakerDaoUsdsAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract MakerDaoUsdsAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC4626 private constant S_USDS = IERC4626(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);
    IERC20 private constant USDS = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    MakerDaoUsdsAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDS), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(95, 100), address(S_USDS), address(USDC));

        LevvaVault levvaVaultImplementation = new LevvaVault();
        bytes memory data = abi.encodeWithSelector(
            LevvaVault.initialize.selector, USDC, "lpName", "lpSymbol", address(0xFEE), address(oracle)
        );
        levvaVault = LevvaVault(address(new ERC1967Proxy(address(levvaVaultImplementation), data)));

        adapter = new MakerDaoUsdsAdapter(address(S_USDS));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDS), address(levvaVault), 10 ** 24);

        levvaVault.addTrackedAsset(address(USDS));
        levvaVault.addTrackedAsset(address(S_USDS));
    }

    function testSetup() public view {
        assertEq(adapter.sUSDS(), address(S_USDS));
        assertEq(adapter.USDS(), address(USDS));
    }

    function testDeposit() public {
        uint256 usrBalanceBefore = USDS.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(usrBalanceBefore - USDS.balanceOf(address(levvaVault)), depositAmount);
        assertEq(S_USDS.balanceOf(address(levvaVault)), expectedLpTokens);
        assertEq(USDS.balanceOf(address(adapter)), 0);
        assertEq(S_USDS.balanceOf(address(adapter)), 0);
    }

    function testDepositNotTrackedAsset() public {
        levvaVault.removeTrackedAsset(address(S_USDS));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, S_USDS));
        adapter.deposit(1000 * 10 ** 18);
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = USDS.balanceOf(address(levvaVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(levvaVault));
        adapter.redeem(expectedLpTokens);

        assertApproxEqAbs(USDS.balanceOf(address(levvaVault)), usdeBalanceBefore, 1);
        assertEq(S_USDS.balanceOf(address(levvaVault)), 0);
        assertEq(USDS.balanceOf(address(adapter)), 0);
        assertEq(S_USDS.balanceOf(address(adapter)), 0);
    }

    function testRedeemNotTrackedAsset() public {
        uint256 depositAmount = USDS.balanceOf(address(levvaVault));
        vm.prank(address(levvaVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        levvaVault.removeTrackedAsset(address(USDS));

        vm.prank(address(levvaVault));
        vm.expectRevert(abi.encodeWithSelector(AdapterBase.AdapterBase__InvalidToken.selector, USDS));
        adapter.redeem(expectedLpTokens);
    }
}
