// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LevvaPoolAdapter} from "../../contracts/adapters/levvaPool/LevvaPoolAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {ILevvaPool} from "../../contracts/adapters/levvaPool/interfaces/ILevvaPool.sol";
import {FP96} from "../../contracts/adapters/levvaPool/FP96.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {LevvaPoolMock} from "../mocks/LevvaPoolMock.t.sol";

contract LevvaPoolAdapterHarness is LevvaPoolAdapter {
    constructor(address vault) LevvaPoolAdapter(vault) {}

    function exposed_addPool(address pool) external {
        _addPool(pool);
    }

    function exposed_removePool(address pool) external {
        _removePool(pool);
    }
}

contract LevvaPoolAdapterTest is Test {
    using FP96 for ILevvaPool.FixedPoint;
    using Math for uint256;

    uint256 private constant X96_ONE = 2 ** 96;
    uint256 private constant FORK_BLOCK_NUMBER = 22497400;

    IERC20 private WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private PT_weETH = IERC20(0xEF6122835a2Bbf575D0117D394fDa24aB7d09d4E);
    IERC20 private weETH = IERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);

    address private PT_weETH_WETH_POOL = 0xE4f8e21B73d711018139011537197940677Cb820; // farming pool, only long
    address private weETH_WETH_POOL = 0x68f61128DeCd74b63f5b76Dc133A4C3F74319DF5; // trade pool, long, short available

    LevvaPoolAdapter internal adapter;

    LevvaVault internal vault;
    EulerRouterMock internal oracle;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK_NUMBER);
        vm.skip(block.chainid != 1, "Only mainnet fork test");

        oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(WETH), address(WETH));
        oracle.setPrice(oracle.ONE(), address(PT_weETH), address(WETH));
        oracle.setPrice(oracle.ONE(), address(weETH), address(WETH));

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

        vault = LevvaVault(deployedVault);

        vault.addTrackedAsset(address(weETH));
        vault.addTrackedAsset(address(PT_weETH));

        adapter = new LevvaPoolAdapter(address(vault));
        vault.addAdapter(address(adapter));

        _fundLevvaPool(weETH_WETH_POOL);

        deal(address(WETH), address(vault), 1000e18);
        deal(address(PT_weETH), address(vault), 1000e18);
        deal(address(weETH), address(vault), 1000e18);
    }

    function test_getVault() public view {
        assertEq(adapter.getVault(), address(vault));
    }

    function test_constructorShouldFailWhenZeroVaultAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        new LevvaPoolAdapter(address(0));
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IExternalPositionAdapter).interfaceId));
    }

    function test_getAdapterId() public view {
        assertEq(adapter.getAdapterId(), bytes4(keccak256("LevvaPoolAdapter")));
    }

    function test_depositQuote() public {
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 10e18;

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);

        vm.expectEmit(true, true, false, false);
        emit LevvaPoolAdapter.PoolAdded(PT_weETH_WETH_POOL);

        vm.prank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, address(pool), 0, 0);
        skip(30 days);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertApproxEqAbs(amounts[0], depositAmount, 10);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(0));

        assertEq(debtAmounts.length, 1);
        assertEq(debtAmounts[0], 0);

        pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(pool));

        _showAssets();
    }

    function test_depositAllExcept() public {
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 exceptAmount = 995e18;
        uint256 depositAmount = IERC20(WETH).balanceOf(address(vault)) - exceptAmount;

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);

        vm.prank(address(vault));
        adapter.depositAllExcept(address(WETH), exceptAmount, 0, false, address(pool), 0, 0);
        skip(30 days);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertApproxEqAbs(amounts[0], depositAmount, 10);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(0));

        assertEq(debtAmounts.length, 1);
        assertEq(debtAmounts[0], 0);

        pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(pool));

        _showAssets();
    }

    function test_depositQuoteAndLong() public {
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        int256 longAmount = -4e18;

        uint256 swapCallData = pool.defaultSwapCallData();
        ILevvaPool.FixedPoint memory basePrice = pool.getBasePrice();
        uint256 limitPriceX96 = basePrice.inner.mulDiv(110, 100);

        vm.prank(address(vault));
        adapter.deposit(address(WETH), depositAmount, longAmount, false, address(pool), limitPriceX96, swapCallData);

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Long));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(PT_weETH.balanceOf(address(adapter)), 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(PT_weETH));

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(WETH));
        assertEq(debtAmounts.length, 1);
        assertTrue(debtAmounts[0] > 0);
    }

    function test_depositBase() public {
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 10e18;
        vm.prank(address(vault));
        adapter.deposit(address(PT_weETH), depositAmount, 0, false, address(pool), 0, 0);
        skip(30 days);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(PT_weETH));
        assertApproxEqAbs(amounts[0], depositAmount, 10);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(0));

        assertEq(debtAmounts.length, 1);
        assertEq(debtAmounts[0], 0);

        _showAssets();
    }

    function test_depositBaseAndShort() public {
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        int256 shortAmount = -4e18;

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(90, 100);

        vm.prank(address(vault));
        adapter.deposit(address(weETH), depositAmount, shortAmount, false, address(pool), limitPriceX96, swapCallData);
        skip(30 days);

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Short));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(adapter)), 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertTrue(amounts[0] > 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(weETH));
        assertEq(debtAmounts.length, 1);
        assertTrue(debtAmounts[0] > 0);
    }

    function test_depositQuoteAndShortCoeffs() public {
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);
        _openPositionsInPool(weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        int256 shortAmount = 5e18;

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(90, 100);

        vm.prank(address(vault));
        adapter.deposit(address(WETH), depositAmount, shortAmount, false, address(pool), limitPriceX96, swapCallData);
        //check coeffs before reinit
        (, uint256[] memory amounts) = adapter.getManagedAssets();
        (, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        uint256 quoteCollateral = amounts[0];
        uint256 baseDebt = debtAmounts[0];

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(ILevvaPool.PositionType.Short), uint8(position._type));
        uint256 actualQuoteCollateral =
            pool.quoteCollateralCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);
        uint256 actualBaseDebt = pool.baseDebtCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);

        assertEq(quoteCollateral, actualQuoteCollateral, "wrong quote collateral before reinit");
        assertEq(baseDebt, actualBaseDebt, "wrong base debt before reinit");

        skip(60 days);

        //check coeffs after reinit
        (, amounts) = adapter.getManagedAssets();
        (, debtAmounts) = adapter.getDebtAssets();
        quoteCollateral = amounts[0];
        baseDebt = debtAmounts[0];

        //reinit
        pool.execute(ILevvaPool.CallType.Reinit, 0, 0, 0, false, address(0), 0);

        position = pool.positions(address(adapter));
        actualQuoteCollateral = pool.quoteCollateralCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);
        actualBaseDebt = pool.baseDebtCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);

        assertEq(quoteCollateral, actualQuoteCollateral, "wrong quote collateral after reinit");
        assertEq(baseDebt, actualBaseDebt, "wrong base debt after reinit");
    }

    function test_depositBaseAndLongCoeffs() public {
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);
        _openPositionsInPool(weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        int256 longAmount = 5e18;

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(110, 100);

        vm.prank(address(vault));
        adapter.deposit(address(weETH), depositAmount, longAmount, false, address(pool), limitPriceX96, swapCallData);
        //check coeffs before reinit
        (, uint256[] memory amounts) = adapter.getManagedAssets();
        (, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        uint256 baseCollateral = amounts[0];
        uint256 quoteDebt = debtAmounts[0];

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(ILevvaPool.PositionType.Long), uint8(position._type));
        uint256 actualBaseCollateral = pool.baseCollateralCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);
        uint256 actualQuoteDebt = pool.quoteDebtCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);

        assertEq(baseCollateral, actualBaseCollateral, "wrong base collateral before reinit");
        assertEq(quoteDebt, actualQuoteDebt, "wrong base debt before reinit");

        skip(60 days);

        //check coeffs after reinit
        (, amounts) = adapter.getManagedAssets();
        (, debtAmounts) = adapter.getDebtAssets();
        baseCollateral = amounts[0];
        quoteDebt = debtAmounts[0];

        //reinit
        pool.execute(ILevvaPool.CallType.Reinit, 0, 0, 0, false, address(0), 0);

        position = pool.positions(address(adapter));
        actualBaseCollateral = pool.baseCollateralCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);
        actualQuoteDebt = pool.quoteDebtCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);

        assertEq(baseCollateral, actualBaseCollateral, "wrong quote collateral after reinit");
        assertEq(quoteDebt, actualQuoteDebt, "wrong quote debt after reinit");
    }

    function test_depositBaseCoeffs() public {
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);
        _openPositionsInPool(weETH_WETH_POOL);
        uint256 depositAmount = 1e18;

        vm.prank(address(vault));
        adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);
        //check coeffs before reinit
        (, uint256[] memory amounts) = adapter.getManagedAssets();
        uint256 baseCollateral = amounts[0];

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(ILevvaPool.PositionType.Lend), uint8(position._type));
        uint256 actualBaseCollateral = pool.baseCollateralCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);

        assertEq(baseCollateral, actualBaseCollateral, "wrong base collateral before reinit");

        skip(30 days);

        //check coeffs after reinit
        (, amounts) = adapter.getManagedAssets();
        baseCollateral = amounts[0];
        uint256 blockTimestamp = block.timestamp;

        //reinit
        pool.execute(ILevvaPool.CallType.Reinit, 0, 0, 0, false, address(0), 0);

        assertEq(block.timestamp, blockTimestamp);

        position = pool.positions(address(adapter));
        actualBaseCollateral = pool.baseCollateralCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);

        assertEq(baseCollateral, actualBaseCollateral, "wrong base collateral after reinit");
    }

    function test_depositQuoteCoeffs() public {
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);
        _openPositionsInPool(weETH_WETH_POOL);
        uint256 depositAmount = 1e18;

        vm.prank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, address(pool), 0, 0);
        //check coeffs before reinit
        (, uint256[] memory amounts) = adapter.getManagedAssets();
        uint256 quoteCollateral = amounts[0];

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(ILevvaPool.PositionType.Lend), uint8(position._type));
        uint256 actualQuoteCollateral =
            pool.quoteCollateralCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);

        assertEq(quoteCollateral, actualQuoteCollateral, "wrong base collateral before reinit");

        skip(30 days);

        //check coeffs after reinit
        (, amounts) = adapter.getManagedAssets();
        quoteCollateral = amounts[0];
        uint256 blockTimestamp = block.timestamp;

        //reinit
        pool.execute(ILevvaPool.CallType.Reinit, 0, 0, 0, false, address(0), 0);

        assertEq(block.timestamp, blockTimestamp);

        position = pool.positions(address(adapter));
        actualQuoteCollateral = pool.quoteCollateralCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);

        assertEq(quoteCollateral, actualQuoteCollateral, "wrong base collateral after reinit");
    }

    function test_depositQuoteAndLongShouldFailWhenOracleNotExists() public {
        oracle.removePrice(address(WETH), address(WETH));
        uint256 depositAmount = 1e18;
        int256 longAmount = -4e18;

        uint256 swapCallData = ILevvaPool(PT_weETH_WETH_POOL).defaultSwapCallData();
        ILevvaPool.FixedPoint memory basePrice = ILevvaPool(PT_weETH_WETH_POOL).getBasePrice();
        uint256 limitPriceX96 = basePrice.inner.mulDiv(110, 100);

        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LevvaPoolAdapter.LevvaPoolAdapter__OracleNotExists.selector, address(WETH), address(WETH)
            )
        );
        adapter.deposit(
            address(WETH), depositAmount, longAmount, false, PT_weETH_WETH_POOL, limitPriceX96, swapCallData
        );
    }

    function test_depositBaseAndShortShouldFailWhenOracleNotExists() public {
        oracle.removePrice(address(weETH), address(WETH));
        uint256 depositAmount = 1e18;
        int256 shortAmount = -4e18;

        uint256 swapCallData = ILevvaPool(weETH_WETH_POOL).defaultSwapCallData();
        ILevvaPool.FixedPoint memory basePrice = ILevvaPool(weETH_WETH_POOL).getBasePrice();
        uint256 limitPriceX96 = basePrice.inner.mulDiv(110, 100);

        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LevvaPoolAdapter.LevvaPoolAdapter__OracleNotExists.selector, address(weETH), address(WETH)
            )
        );
        adapter.deposit(address(weETH), depositAmount, shortAmount, false, weETH_WETH_POOL, limitPriceX96, swapCallData);
    }

    function test_depositShouldFailWhenNotAuthorized() public {
        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__NotAuthorized.selector);
        adapter.deposit(address(0), 0, 0, false, address(0), 0, 0);
    }

    function test_depositBaseQuoteShouldFailWhenNotSupported() public {
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);
        uint256 depositAmount = 1e18;

        vm.startPrank(address(vault));
        adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);

        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__NotSupported.selector);
        adapter.deposit(address(WETH), depositAmount, 0, false, address(pool), 0, 0);
    }

    function test_depositQuoteBaseShouldFailWhenNotSupported() public {
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);
        uint256 depositAmount = 1e18;

        vm.startPrank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, address(pool), 0, 0);

        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__NotSupported.selector);
        adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);
    }

    function test_partialWithdraw() public {
        // deposit first
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 5e18;
        vm.startPrank(address(vault));
        adapter.deposit(address(PT_weETH), depositAmount, 0, false, address(pool), 0, 0);

        //withdraw
        uint256 withdrawAmount = 4e18;
        adapter.withdraw(address(PT_weETH), withdrawAmount, address(pool));

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Lend));

        _showAssets();
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts[0], depositAmount - withdrawAmount);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAmounts[0], 0);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(pool));
    }

    function test_withdrawBase() public {
        // deposit first
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        vm.startPrank(address(vault));
        adapter.deposit(address(PT_weETH), depositAmount, 0, false, address(pool), 0, 0);
        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Lend));

        //withdraw
        vm.expectEmit(true, true, false, false);
        emit LevvaPoolAdapter.PoolRemoved(PT_weETH_WETH_POOL);
        uint256 withdrawAmount = type(uint256).max;
        adapter.withdraw(address(PT_weETH), withdrawAmount, address(pool));

        position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Uninitialized));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);
    }

    function test_withdrawQuote() public {
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        vm.startPrank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, address(pool), 0, 0);
        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Lend));

        //withdraw
        uint256 withdrawAmount = type(uint256).max;
        adapter.withdraw(address(WETH), withdrawAmount, address(pool));

        position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Uninitialized));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);
    }

    function test_withdrawShouldFailWhenNotAuthorized() public {
        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__NotAuthorized.selector);
        adapter.withdraw(address(0), 0, address(0));
    }

    function test_closePosition() public {
        //open short position
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        int256 shortAmount = -2e18;

        uint256 swapCallData = pool.defaultSwapCallData();
        ILevvaPool.FixedPoint memory basePrice = pool.getBasePrice();
        uint256 limitPriceX96 = basePrice.inner.mulDiv(90, 100);

        vm.startPrank(address(vault));
        adapter.deposit(address(weETH), depositAmount, shortAmount, false, address(pool), limitPriceX96, swapCallData);

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Short));

        //close position
        limitPriceX96 = basePrice.inner.mulDiv(110, 100);
        adapter.closePosition(address(pool), false, limitPriceX96, swapCallData);
        position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Lend));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAmounts.length, 1);
    }

    function test_closePositionShouldFailWhenNotAuthorized() public {
        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__NotAuthorized.selector);
        adapter.closePosition(address(weETH_WETH_POOL), false, 0, 0);
    }

    function test_long() public {
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        uint256 longAmount = 3e18; // long 3 WETH

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(110, 100);

        vm.startPrank(address(vault));
        adapter.deposit(address(PT_weETH), depositAmount, 0, false, address(pool), 0, 0);
        adapter.long(longAmount, false, address(pool), limitPriceX96, swapCallData);
        skip(30 days);

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Long));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(PT_weETH.balanceOf(address(adapter)), 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(PT_weETH));
        assertApproxEqAbs(amounts[0], depositAmount + longAmount, 10);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(WETH));

        assertEq(debtAmounts.length, 1);
        assertTrue(debtAmounts[0] > 0);

        _showAssets();
    }

    function test_longShouldFailWhenNotAuthorized() public {
        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__NotAuthorized.selector);
        adapter.long(0, false, address(weETH_WETH_POOL), 0, 0);
    }

    function test_short() public {
        uint256 depositAmount = 1e18;
        uint256 shortAmount = 4e18;
        ILevvaPool pool = ILevvaPool(weETH_WETH_POOL);

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(90, 100);

        vm.startPrank(address(vault));
        adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);
        adapter.short(shortAmount, false, address(pool), limitPriceX96, swapCallData);
        skip(30 days);

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Short));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(adapter)), 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertTrue(amounts[0] > 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(weETH));

        assertEq(debtAmounts.length, 1);
        assertGe(debtAmounts[0], shortAmount);

        _showAssets();
    }

    function test_shortShouldFailWhenNoAuthorized() public {
        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__NotAuthorized.selector);
        adapter.short(0, false, address(weETH_WETH_POOL), 0, 0);
    }

    function test_depositQuoteLong() public {
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 1e18; // deposit 1 WETH and flip to PT-weETH
        int256 longAmount = -3e18; // long 3 WETH

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(110, 100);

        vm.prank(address(vault));
        adapter.deposit(address(WETH), depositAmount, longAmount, false, address(pool), limitPriceX96, swapCallData);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(PT_weETH.balanceOf(address(adapter)), 0);

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Long));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(PT_weETH));

        assertEq(amounts.length, 1);
        assertTrue(amounts[0] > 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(WETH));

        assertEq(debtAmounts.length, 1);
        assertTrue(debtAmounts[0] > 0);

        _showAssets();
    }

    function test_depositBaseAndLong() public {
        ILevvaPool pool = ILevvaPool(PT_weETH_WETH_POOL);
        uint256 depositAmount = 1e18;
        int256 longAmount = 3e18; // long 3 WETH

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(110, 100);

        vm.prank(address(vault));
        adapter.deposit(address(PT_weETH), depositAmount, longAmount, false, address(pool), limitPriceX96, swapCallData);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(PT_weETH.balanceOf(address(adapter)), 0);

        ILevvaPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(ILevvaPool.PositionType.Long));

        _showAssets();
    }

    function test_depositTwoTimes() public {
        uint256 depositAmount = 1e18; // deposit 1 WETH and flip to PT-weETH
        deal(address(WETH), address(vault), depositAmount * 2);

        vm.startPrank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, PT_weETH_WETH_POOL, 0, 0);
        adapter.deposit(address(WETH), depositAmount, 0, false, PT_weETH_WETH_POOL, 0, 0);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(PT_weETH.balanceOf(address(adapter)), 0);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(PT_weETH_WETH_POOL));
    }

    function test_removePoolsAfterWithdraw() public {
        uint256 depositAmount = 1e18; // deposit 1 WETH and flip to PT-weETH
        deal(address(WETH), address(vault), depositAmount * 2);

        vm.startPrank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, PT_weETH_WETH_POOL, 0, 0);
        adapter.deposit(address(WETH), depositAmount, 0, false, weETH_WETH_POOL, 0, 0);

        adapter.withdraw(address(WETH), type(uint256).max, PT_weETH_WETH_POOL);
        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(weETH_WETH_POOL));
    }

    function test_emergencyWithdrawQuote() public {
        //deposit quote
        LevvaPoolMock pool = new LevvaPoolMock(address(weETH), address(WETH));
        deal(address(weETH), address(pool), 10e18);
        deal(address(WETH), address(pool), 10e18);

        uint256 depositAmount = 1e18;
        deal(address(WETH), address(vault), depositAmount * 2);
        vm.startPrank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(ILevvaPool.PositionType.Lend, depositAmount, 0);
        pool.setMode(ILevvaPool.Mode.LongEmergency);

        uint256 baseBalanceBefore = WETH.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(adapter)), 0);
        assertGe(WETH.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawBase() public {
        //deposit base
        LevvaPoolMock pool = new LevvaPoolMock(address(weETH), address(WETH));
        deal(address(weETH), address(pool), 10e18);
        deal(address(WETH), address(pool), 10e18);

        uint256 depositAmount = 1e18;
        deal(address(weETH), address(vault), depositAmount * 2);
        vm.startPrank(address(vault));
        adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(ILevvaPool.PositionType.Lend, depositAmount, 0);
        pool.setMode(ILevvaPool.Mode.ShortEmergency);
        uint256 baseBalanceBefore = weETH.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(adapter)), 0);
        assertGe(weETH.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdraw_ShortAndShortEmergency() public {
        //deposit quote
        LevvaPoolMock pool = new LevvaPoolMock(address(weETH), address(WETH));
        deal(address(weETH), address(pool), 10e18);
        deal(address(WETH), address(pool), 10e18);

        uint256 depositAmount = 1e18;
        uint256 shortAmount = 2e18;
        deal(address(WETH), address(vault), depositAmount);
        vm.startPrank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(ILevvaPool.PositionType.Short, depositAmount, shortAmount);
        pool.setMode(ILevvaPool.Mode.ShortEmergency);

        uint256 baseBalanceBefore = WETH.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(adapter)), 0);
        assertEq(WETH.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawLongAndLongEmergency() public {
        //deposit base
        LevvaPoolMock pool = new LevvaPoolMock(address(weETH), address(WETH));
        deal(address(weETH), address(pool), 10e18);
        deal(address(WETH), address(pool), 10e18);

        uint256 depositAmount = 1e18;
        uint256 longAmount = 3e18;
        deal(address(weETH), address(vault), depositAmount * 2);
        vm.startPrank(address(vault));
        adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(ILevvaPool.PositionType.Long, depositAmount, longAmount);
        pool.setMode(ILevvaPool.Mode.LongEmergency);
        uint256 baseBalanceBefore = weETH.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawLongAndShortEmergency() public {
        //deposit base
        LevvaPoolMock pool = new LevvaPoolMock(address(weETH), address(WETH));
        deal(address(weETH), address(pool), 10e18);
        deal(address(WETH), address(pool), 10e18);

        uint256 depositAmount = 1e18;
        uint256 longAmount = 3e18;
        deal(address(weETH), address(vault), depositAmount * 2);
        vm.startPrank(address(vault));
        adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(ILevvaPool.PositionType.Long, depositAmount, longAmount);
        pool.setMode(ILevvaPool.Mode.ShortEmergency);
        uint256 baseBalanceBefore = weETH.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(adapter)), 0);
        assertGt(weETH.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawShortAndLongEmergency() public {
        //deposit quote
        LevvaPoolMock pool = new LevvaPoolMock(address(weETH), address(WETH));
        deal(address(weETH), address(pool), 10e18);
        deal(address(WETH), address(pool), 10e18);

        uint256 depositAmount = 1e18;
        uint256 shortAmount = 2e18;
        deal(address(WETH), address(vault), depositAmount);
        vm.startPrank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(ILevvaPool.PositionType.Short, depositAmount, shortAmount);
        pool.setMode(ILevvaPool.Mode.LongEmergency);

        uint256 baseBalanceBefore = WETH.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(weETH.balanceOf(address(adapter)), 0);
        assertGt(WETH.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawShouldFailWhenWrongLevvaPoolMode() public {
        uint256 depositAmount = 1e18; // deposit 1 WETH and flip to PT-weETH
        deal(address(WETH), address(vault), depositAmount * 2);

        vm.startPrank(address(vault));
        adapter.deposit(address(WETH), depositAmount, 0, false, PT_weETH_WETH_POOL, 0, 0);

        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__WrongLevvaPoolMode.selector);
        adapter.emergencyWithdraw(PT_weETH_WETH_POOL);
    }

    function test_addPool() public {
        LevvaPoolAdapterHarness harness = new LevvaPoolAdapterHarness(address(1));
        harness.exposed_addPool(address(2));
        harness.exposed_addPool(address(3));
        harness.exposed_addPool(address(4));

        address[] memory pools = harness.getPools();
        assertEq(pools.length, 3);
        assertEq(pools[0], address(2));
        assertEq(pools[1], address(3));
        assertEq(pools[2], address(4));

        assertEq(harness.getPoolPosition(address(2)), 1);
        assertEq(harness.getPoolPosition(address(3)), 2);
        assertEq(harness.getPoolPosition(address(4)), 3);

        harness.exposed_removePool(address(2));
        assertEq(harness.getPoolPosition(address(4)), 1);
        assertEq(harness.getPoolPosition(address(3)), 2);
    }

    function test_removePoolShouldFail() public {
        LevvaPoolAdapterHarness harness = new LevvaPoolAdapterHarness(address(1));
        vm.expectRevert(LevvaPoolAdapter.LevvaPoolAdapter__NoPool.selector);
        harness.exposed_removePool(address(1));
    }

    function _showAssets() private view {
        address[] memory levvaPools = adapter.getPools();
        console.log("Pool positions:");
        for (uint256 i = 0; i < levvaPools.length; i++) {
            _showPosition(levvaPools[i]);
        }

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        console.log("Managed assets:");
        for (uint256 i = 0; i < assets.length; i++) {
            console.log(" ", ERC20(assets[i]).symbol(), amounts[i]);
        }

        console.log("Debt assets:");
        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        for (uint256 i = 0; i < debtAssets.length; i++) {
            if (debtAssets[i] != address(0)) {
                console.log(" ", ERC20(debtAssets[i]).symbol(), debtAmounts[i]);
            }
        }
    }

    function _showPosition(address pool) private view {
        ILevvaPool.Position memory position = ILevvaPool(pool).positions(address(adapter));

        string memory typeStr = "Uninitialized";
        if (position._type == ILevvaPool.PositionType.Lend) {
            typeStr = "Lend";
        } else if (position._type == ILevvaPool.PositionType.Short) {
            typeStr = "Short";
        } else if (position._type == ILevvaPool.PositionType.Long) {
            typeStr = "Long";
        }

        console.log(
            " ", ERC20(ILevvaPool(pool).baseToken()).symbol(), "/", ERC20(ILevvaPool(pool).quoteToken()).symbol()
        );
        console.log("   type: ", typeStr);
        console.log("   base  amount: ", position.discountedBaseAmount);
        console.log("   quote amount: ", position.discountedQuoteAmount);
    }

    function _openPositionsInPool(address pool) private {
        ERC20 quoteToken = ERC20(ILevvaPool(pool).quoteToken());
        ERC20 baseToken = ERC20(ILevvaPool(pool).baseToken());

        uint256 quoteDepositAmount = 1 * 10 ** quoteToken.decimals();
        uint256 baseDepositAmount = 1 * 10 ** baseToken.decimals();

        {
            address longer = makeAddr("LONGER");
            int256 longAmount = 5 * int256(baseDepositAmount);
            deal(address(baseToken), address(longer), baseDepositAmount);
            startHoax(longer);
            baseToken.approve(pool, baseDepositAmount);
            ILevvaPool(pool).execute(
                ILevvaPool.CallType.DepositBase,
                baseDepositAmount,
                longAmount,
                ILevvaPool(pool).getBasePrice().inner.mulDiv(110, 100),
                false,
                address(0),
                ILevvaPool(pool).defaultSwapCallData()
            );
            vm.stopPrank();
        }

        {
            address shorter = makeAddr("SHORTER");
            int256 shortAmount = 5 * int256(baseDepositAmount);
            deal(address(quoteToken), address(shorter), quoteDepositAmount);
            startHoax(shorter);
            quoteToken.approve(pool, quoteDepositAmount);
            ILevvaPool(pool).execute(
                ILevvaPool.CallType.DepositQuote,
                quoteDepositAmount,
                shortAmount,
                ILevvaPool(pool).getBasePrice().inner.mulDiv(90, 100),
                false,
                address(0),
                ILevvaPool(pool).defaultSwapCallData()
            );
            vm.stopPrank();
        }
    }

    function _fundLevvaPool(address pool) private {
        address user = makeAddr("funder");
        ERC20 quoteToken = ERC20(ILevvaPool(pool).quoteToken());
        ERC20 baseToken = ERC20(ILevvaPool(pool).baseToken());

        uint256 quoteDepositAmount = 100 * 10 ** quoteToken.decimals();
        uint256 baseDepositAmount = 100 * 10 ** baseToken.decimals();

        deal(address(quoteToken), address(user), quoteDepositAmount);
        deal(address(baseToken), address(user), baseDepositAmount);
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        quoteToken.approve(pool, quoteDepositAmount);
        ILevvaPool(pool).execute(
            ILevvaPool.CallType.DepositQuote,
            quoteDepositAmount,
            0,
            0,
            false,
            address(0),
            ILevvaPool(pool).defaultSwapCallData()
        );

        baseToken.approve(pool, baseDepositAmount);
        ILevvaPool(pool).execute(
            ILevvaPool.CallType.DepositBase,
            baseDepositAmount,
            0,
            0,
            false,
            address(0),
            ILevvaPool(pool).defaultSwapCallData()
        );

        vm.stopPrank();
    }
}
