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
import {OriginETHTechAdapter} from "../../contracts/adapters/origin/OriginETHTechAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {IOETHVault} from "../../contracts/adapters/origin/interfaces/IOETHVault.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract OriginETHTechAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant OETH = IERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);
    IERC20 private constant W_OETH = IERC20(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    OriginETHTechAdapter private adapter;
    LevvaVault private levvaVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(11, 10), address(W_OETH), address(WETH));
        oracle.setPrice(oracle.ONE(), address(OETH), address(WETH));

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

        adapter = new OriginETHTechAdapter(address(W_OETH));
        levvaVault.addAdapter(address(adapter));
        assertEq(levvaVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(W_OETH), address(levvaVault), 10 ether);

        levvaVault.addTrackedAsset(address(W_OETH));
        levvaVault.addTrackedAsset(address(OETH));
    }

    function testInit() public view {
        assertEq(address(adapter.wrappedOETH()), address(W_OETH));
    }

    function testAddressZeroRevert() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        new OriginETHTechAdapter(address(0));
    }

    function testUnwrap() public {
        uint256 wOEthBalanceBefore = W_OETH.balanceOf(address(levvaVault));
        uint256 oEthBalanceBefore = OETH.balanceOf(address(levvaVault));

        uint256 unwrapAmount = 1 ether;
        vm.prank(address(levvaVault));
        (uint256 oETHAmount) = adapter.unwrap(unwrapAmount);


        assertEq(wOEthBalanceBefore - W_OETH.balanceOf(address(levvaVault)), unwrapAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), oEthBalanceBefore + oETHAmount);
    }

    function testUnwrapAllExcept() public {
        uint256 oEthBalanceBefore = OETH.balanceOf(address(levvaVault));

        uint256 unwrapExceptAmount = 1 ether;
        vm.prank(address(levvaVault));
        (uint256 oETHAmount) = adapter.unwrapAllExcept(unwrapExceptAmount);


        assertEq(W_OETH.balanceOf(address(levvaVault)), unwrapExceptAmount);
        assertEq(OETH.balanceOf(address(levvaVault)), oEthBalanceBefore + oETHAmount);
    }
}
