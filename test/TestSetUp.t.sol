// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LevvaVaultFactory} from "../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../contracts/LevvaVault.sol";
import {WithdrawalQueue} from "../contracts/WithdrawalQueue.sol";
import {MintableERC20} from "./mocks/MintableERC20.t.sol";
import {AdapterMock} from "./mocks/AdapterMock.t.sol";
import {EulerRouterMock} from "./mocks/EulerRouterMock.t.sol";
import {ExternalPositionAdapterMock} from "./mocks/ExternalPositionAdapterMock.t.sol";

contract TestSetUp is Test {
    using Math for uint256;

    string internal constant LP_NAME = "lpName";
    string internal constant LP_SYMBOL = "lpSymbol";

    address internal constant NO_ACCESS = address(0xDEAD);
    address internal constant VAULT_MANAGER = address(0x123456789);
    address internal constant FINALIZER = address(0x1234567890);
    address internal constant FEE_COLLECTOR = address(0xFEE);
    address internal constant USER = address(0x987654321);

    LevvaVaultFactory internal levvaVaultFactoryImplementation;
    ERC1967Proxy internal levvaVaultFactoryProxy;
    LevvaVaultFactory internal levvaVaultFactory;

    LevvaVault internal levvaVaultImplementation;
    LevvaVault internal levvaVault;

    WithdrawalQueue internal withdrawalQueueImplementation;
    WithdrawalQueue internal withdrawalQueue;

    MintableERC20 internal asset;
    MintableERC20 internal trackedAsset;
    MintableERC20 internal externalPositionManagedAsset;
    MintableERC20 internal externalPositionDebtAsset;

    AdapterMock internal adapter;
    ExternalPositionAdapterMock internal externalPositionAdapter;
    EulerRouterMock internal oracle;

    function setUp() public virtual {
        _createOracleMock();
        _createAssets();
        _createAdapterMocks();
        _createLevvaVaultFactory();
        _deployLevvaVault();
    }

    function testInitialize() public view {
        assertEq(address(levvaVault.asset()), address(asset));
        assertEq(levvaVault.owner(), address(this));
        assertEq(levvaVault.name(), LP_NAME);
        assertEq(levvaVault.symbol(), LP_SYMBOL);
        assertEq(levvaVault.getFeeCollectorStorage().feeCollector, FEE_COLLECTOR);
        assertEq(levvaVault.getFeeCollectorStorage().highWaterMarkPerShare, 10 ** levvaVault.decimals());
        assertEq(address(levvaVault.oracle()), address(oracle));
        assertEq(levvaVault.withdrawalQueue(), address(withdrawalQueue));
        assert(levvaVault.isVaultManager(VAULT_MANAGER));

        assertEq(address(withdrawalQueue.levvaVault()), address(levvaVault));
        assert(withdrawalQueue.isFinalizer(FINALIZER));
    }

    function _createLevvaVaultFactory() private {
        levvaVaultImplementation = new LevvaVault();
        withdrawalQueueImplementation = new WithdrawalQueue();

        levvaVaultFactoryImplementation = new LevvaVaultFactory();
        bytes memory data = abi.encodeWithSelector(
            LevvaVaultFactory.initialize.selector,
            address(levvaVaultImplementation),
            address(withdrawalQueueImplementation)
        );
        levvaVaultFactoryProxy = new ERC1967Proxy(address(levvaVaultFactoryImplementation), data);
        levvaVaultFactory = LevvaVaultFactory(address(levvaVaultFactoryProxy));
    }

    function _deployLevvaVault() private {
        (address vault, address queue) =
            levvaVaultFactory.deployVault(address(asset), LP_NAME, LP_SYMBOL, FEE_COLLECTOR, address(oracle));

        levvaVault = LevvaVault(vault);
        withdrawalQueue = WithdrawalQueue(queue);

        levvaVault.addVaultManager(VAULT_MANAGER, true);
        withdrawalQueue.addFinalizer(FINALIZER, true);
    }

    function _createOracleMock() private {
        oracle = new EulerRouterMock();
    }

    function _createAssets() private {
        asset = new MintableERC20("USDTest", "USDTest", 6);

        trackedAsset = new MintableERC20("ETHest", "ETHest", 18);
        oracle.setPrice(oracle.ONE().mulDiv(2000, 10 ** 12), address(trackedAsset), address(asset));

        externalPositionManagedAsset = new MintableERC20("aUSDTest", "aUSDTest", 6);
        oracle.setPrice(oracle.ONE(), address(externalPositionManagedAsset), address(asset));

        externalPositionDebtAsset = new MintableERC20("variableDebtUSDTest", "variableDebtUSDTest", 6);
        oracle.setPrice(oracle.ONE(), address(externalPositionDebtAsset), address(asset));
    }

    function _createAdapterMocks() private {
        adapter = new AdapterMock();
        externalPositionAdapter =
            new ExternalPositionAdapterMock(address(externalPositionManagedAsset), address(externalPositionDebtAsset));
    }
}
