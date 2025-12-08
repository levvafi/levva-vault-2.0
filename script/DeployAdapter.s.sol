// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ChainValues} from "./helper/ChainValues.sol";
import {DeployHelper} from "./helper/DeployHelper.sol";
import {Adapter, AdapterUtils} from "./helper/AdapterUtils.sol";
import {AaveAdapter} from "contracts/adapters/aave/AaveAdapter.sol";
import {CurveRouterAdapter} from "contracts/adapters/curve/CurveRouterAdapter.sol";
import {CurvePoolAdapter} from "contracts/adapters/curve/CurvePoolAdapter.sol";
import {EthenaAdapter} from "contracts/adapters/ethena/EthenaAdapter.sol";
import {EtherfiETHAdapter} from "contracts/adapters/etherfi/EtherfiETHAdapter.sol";
import {EtherfiBTCAdapter} from "contracts/adapters/etherfi/EtherfiBTCAdapter.sol";
import {LevvaPoolAdapter} from "contracts/adapters/levvaPool/LevvaPoolAdapter.sol";
import {LevvaVaultAdapter} from "contracts/adapters/levvaVault/LevvaVaultAdapter.sol";
import {LidoAdapter} from "contracts/adapters/lido/LidoAdapter.sol";
import {MakerDaoDaiAdapter} from "contracts/adapters/makerDao/MakerDaoDaiAdapter.sol";
import {MakerDaoUsdsAdapter} from "contracts/adapters/makerDao/MakerDaoUsdsAdapter.sol";
import {MorphoAdapter} from "contracts/adapters/morpho/MorphoAdapter.sol";
import {MorphoAdapterV1_1} from "contracts/adapters/morpho/MorphoAdapterV1_1.sol";
import {UniswapAdapter} from "contracts/adapters/uniswap/UniswapAdapter.sol";
import {PendleAdapter} from "contracts/adapters/pendle/PendleAdapter.sol";
import {ResolvAdapter} from "contracts/adapters/resolv/ResolvAdapter.sol";
import {OriginETHAdapter} from "contracts/adapters/origin/OriginETHAdapter.sol";
import {SparkUSDCAdapter} from "contracts/adapters/spark/SparkUSDCAdapter.sol";
import {TokemakAdapter} from "contracts/adapters/tokemak/TokemakAdapter.sol";
import {DeployLevvaVaultFactory} from "./DeployLevvaVaultFactory.s.sol";

/**
 * @dev Uncomment lines you want to deploy
 * @dev source .env && forge script script/DeployAdapter.s.sol:DeployAdapter -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
 */
contract DeployAdapter is DeployHelper, AdapterUtils {
    using stdJson for string;

    string public constant DEPLOYMENT_FILE = "adapters.json";

    function run() public {
        //deployAdapter(Adapter.AaveAdapter, address(0));
        //deployAdapter(Adapter.Curve, address(0));
        //deployAdapter(Adapter.EthenaAdapter, address(0));
        //deployAdapter(Adapter.EtherfiBTC, address(0));
        //deployAdapter(Adapter.EtherfiETH, address(0));
        //deployAdapter(Adapter.LevvaPoolAdapter, address(0));
        //deployAdapter(Adapter.LevvaVaultAdapter, address(0));
        //deployAdapter(Adapter.LidoAdapter, address(0));
        //deployAdapter(Adapter.MakerDaoDaiAdapter, address(0));
        //deployAdapter(Adapter.MakerDaoUsdsAdapter, address(0));
        //deployAdapter(Adapter.MorphoAdapter, address(0));
        //deployAdapter(Adapter.MorphoAdapterV1_1, address(0));
        //deployAdapter(Adapter.PendleAdapter, address(0));
        //deployAdapter(Adapter.UniswapAdapter, address(0));
        //deployAdapter(Adapter.ResolvAdapter, address(0));
        //deployAdapter(Adapter.CurvePoolAdapter, address(0));
        //deployAdapter(Adapter.OriginETHAdapter, address(0));
        //deployAdapter(Adapter.SparkUSDCAdapter, address(0));
        //deployAdapter(Adapter.TokemakAutoUSDAdapter, address(0));
        //deployAdapter(Adapter.TokemakAutoETHAdapter, address(0));
    }

    function getDeployedAdapter(Adapter adapter, address vault) public view returns (address) {
        string memory deploymentKey = _getAdapterName(adapter);
        if (_isPerVaultAdapter(adapter)) {
            deploymentKey = string.concat(deploymentKey, "_", vm.toString(vault));
        }

        return _readAddressFromDeployment(DEPLOYMENT_FILE, deploymentKey);
    }

    function deployAdapterAndConnectToVault(Adapter adapter, address vaultAddress) public {
        address deployedAdapter = deployAdapter(adapter, vaultAddress);

        LevvaVault vault = LevvaVault(vaultAddress);

        vm.broadcast();
        vault.addAdapter(deployedAdapter);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOY ADAPTERS
    //////////////////////////////////////////////////////////////*/

    function getOrDeployAdapter(Adapter adapter, address vault) public returns (address deployedAdapter) {
        deployedAdapter = getDeployedAdapter(adapter, address(vault));
        if (deployedAdapter == address(0)) {
            deployedAdapter = deployAdapter(adapter, address(vault));
        }
    }

    function deployAdapter(Adapter adapter, address levvaVault) public returns (address deployedAdapter) {
        if (adapter == Adapter.AaveAdapter) {
            deployedAdapter = _deployAave();
        } else if (adapter == Adapter.CurveRouterAdapter) {
            deployedAdapter = _deployCurveRouter();
        } else if (adapter == Adapter.EthenaAdapter) {
            deployedAdapter = _deployEthena(levvaVault);
        } else if (adapter == Adapter.EtherfiETH) {
            deployedAdapter = _deployEtherfiETH();
        } else if (adapter == Adapter.EtherfiBTC) {
            deployedAdapter = _deployEtherfiBTC(levvaVault);
        } else if (adapter == Adapter.LevvaPoolAdapter) {
            deployedAdapter = _deployLevvaPool(levvaVault);
        } else if (adapter == Adapter.LevvaVaultAdapter) {
            deployedAdapter = _deployLevvaVault();
        } else if (adapter == Adapter.Lido) {
            deployedAdapter = _deployLido();
        } else if (adapter == Adapter.MakerDaoDAI) {
            deployedAdapter = _deployMakerDaoDai();
        } else if (adapter == Adapter.MakerDaoUSDS) {
            deployedAdapter = _deployMakerDaoUsds();
        } else if (adapter == Adapter.Morpho) {
            deployedAdapter = _deployMorpho();
        } else if (adapter == Adapter.MorphoV1_1) {
            deployedAdapter = _deployMorphoV1_1();
        } else if (adapter == Adapter.PendleAdapter) {
            deployedAdapter = _deployPendle();
        } else if (adapter == Adapter.ResolvAdapter) {
            deployedAdapter = _deployResolv();
        } else if (adapter == Adapter.UniswapAdapter) {
            deployedAdapter = _deployUniswap();
        } else if (adapter == Adapter.CurvePoolAdapter) {
            deployedAdapter = _deployCurvePool();
        } else if (adapter == Adapter.OriginETHAdapter) {
            deployedAdapter = _deployOriginETH();
        } else if (adapter == Adapter.SparkUSDCAdapter) {
            deployedAdapter = _deploySparkUSDC();
        }
        if (deployedAdapter == address(0)) {
            revert("Adapter not supported");
        }

        _saveDeployment(adapter, deployedAdapter, levvaVault);
    }

    function _deployAave() internal returns (address) {
        address aavePoolAddressProvider = getAddress("AavePoolAddressProvider");

        vm.broadcast();
        AaveAdapter aaveAdapter = new AaveAdapter(aavePoolAddressProvider);
        return address(aaveAdapter);
    }

    function _deployResolv() internal returns (address) {
        address wstUSR = getAddress("wstUSR");

        vm.broadcast();
        ResolvAdapter resolvAdapter = new ResolvAdapter(wstUSR);
        return address(resolvAdapter);
    }

    function _deployCurveRouter() internal returns (address) {
        address curveRouter = getAddress("CurveRouterV1_2");

        vm.broadcast();
        CurveRouterAdapter curveRouterAdapter = new CurveRouterAdapter(curveRouter);
        return address(curveRouterAdapter);
    }

    function _deployCurvePool() internal returns (address) {
        address curveNgPoolFactory = getAddress("CurveNgPoolFactory");
        address twoCryptoPoolFactory = getAddress("TwoCryptoPoolFactory");
        address triCryptoPoolFactory = getAddress("TriCryptoPoolFactory");

        vm.broadcast();
        CurvePoolAdapter curvePoolAdapter =
            new CurvePoolAdapter(curveNgPoolFactory, twoCryptoPoolFactory, triCryptoPoolFactory);
        return address(curvePoolAdapter);
    }

    function _deployEthena(address levvaVault) internal returns (address) {
        address sUsde = getAddress("sUSDE");

        vm.broadcast();
        EthenaAdapter ethenaAdapter = new EthenaAdapter(levvaVault, sUsde);
        return address(ethenaAdapter);
    }

    function _deployEtherfiETH() internal returns (address) {
        address weth = getAddress("WETH");
        address weeth = getAddress("weETH");
        address etherfiLiquidityPool = getAddress("EtherFiLiquidityPool");

        vm.broadcast();
        EtherfiETHAdapter etherfiETHAdapter = new EtherfiETHAdapter(weth, weeth, etherfiLiquidityPool);
        return address(etherfiETHAdapter);
    }

    function _deployEtherfiBTC(address levvaVault) internal returns (address) {
        address wbtc = getAddress("WBTC");
        address ebtc = getAddress("eBTC");
        address teller = getAddress("EtherFiBtcTeller");
        address atomicQueue = getAddress("EtherFiBtcAtomicQueue");

        vm.broadcast();
        EtherfiBTCAdapter etherfiBTCAdapter = new EtherfiBTCAdapter(levvaVault, wbtc, ebtc, teller, atomicQueue);
        return address(etherfiBTCAdapter);
    }

    function _deployLevvaVault() internal returns (address) {
        address levvaVaultFactory = getAddress("LevvaVaultFactory");

        vm.broadcast();
        LevvaVaultAdapter levvaVaultAdapter = new LevvaVaultAdapter(levvaVaultFactory);
        return address(levvaVaultAdapter);
    }

    function _deployLevvaPool(address levvaVault) internal returns (address) {
        vm.broadcast();
        LevvaPoolAdapter levvaPoolAdapter = new LevvaPoolAdapter(levvaVault);
        return address(levvaPoolAdapter);
    }

    function _deployLido() internal returns (address) {
        address weth = getAddress("WETH");
        address wsteth = getAddress("wstETH");
        address lidoWithdrawalQueue = getAddress("LidoWithdrawalQueue");

        vm.broadcast();
        LidoAdapter lidoAdapter = new LidoAdapter(weth, wsteth, lidoWithdrawalQueue);
        return address(lidoAdapter);
    }

    function _deployMakerDaoDai() internal returns (address) {
        address sdai = getAddress("sDAI");

        vm.broadcast();
        MakerDaoDaiAdapter makerDaoDAIAdapter = new MakerDaoDaiAdapter(sdai);
        return address(makerDaoDAIAdapter);
    }

    function _deployMakerDaoUsds() internal returns (address) {
        address susds = getAddress("sUSDS");

        vm.broadcast();
        MakerDaoUsdsAdapter makerDaoDAIAdapter = new MakerDaoUsdsAdapter(susds);
        return address(makerDaoDAIAdapter);
    }

    function _deployMorpho() internal returns (address) {
        address morphoFactory = getAddress("MetaMorphoFactory");

        vm.broadcast();
        MorphoAdapter morphoAdapter = new MorphoAdapter(morphoFactory);
        return address(morphoAdapter);
    }

    function _deployMorphoV1_1() internal returns (address) {
        address morphoFactoryV1_1 = getAddress("MetaMorphoFactoryV1_1");

        vm.broadcast();
        MorphoAdapterV1_1 morphoAdapter = new MorphoAdapterV1_1(morphoFactoryV1_1);
        return address(morphoAdapter);
    }

    function _deployPendle() internal returns (address) {
        address pendleRouter = getAddress("PendleRouter");

        vm.broadcast();
        PendleAdapter pendleAdapter = new PendleAdapter(pendleRouter);
        return address(pendleAdapter);
    }

    function _deployUniswap() internal returns (address) {
        address uniswapV3Router = getAddress("UniswapV3Router");
        address universalRouter = getAddress("UniversalRouter");
        address permit2 = getAddress("UniswapPermit2");

        vm.broadcast();
        UniswapAdapter uniswapAdapter = new UniswapAdapter(uniswapV3Router, universalRouter, permit2);
        return address(uniswapAdapter);
    }

    function _deployOriginETH() internal returns (address) {
        address wrappedOETH;
        if (block.chainid == ETHEREUM) {
            wrappedOETH = getAddress("WrappedOETH");
        } else {
            wrappedOETH = getAddress("wrappedSuperOETHb");
        }

        vm.broadcast();
        OriginETHAdapter originETHAdapter = new OriginETHAdapter(wrappedOETH);
        return address(originETHAdapter);
    }

    function _deploySparkUSDC() internal returns (address) {
        address sparkUSDC = getAddress("sparkUSDC");

        vm.broadcast();
        SparkUSDCAdapter sparkUSDCAdapter = new SparkUSDCAdapter(sparkUSDC);
        return address(sparkUSDCAdapter);
    }

    function _deployTokemakAutoUSD() internal returns (address) {
        address autoUSD = getAddress("autoUSD");

        vm.broadcast();
        TokemakAdapter tokemakAutoUSDAdapter = new TokemakAdapter(autoUSD);
        return address(tokemakAutoUSDAdapter);
    }

    function _deployTokemakAutoETH() internal returns (address) {
        address autoETH = getAddress("autoETH");

        vm.broadcast();
        TokemakAdapter tokemakAutoETHAdapter = new TokemakAdapter(autoETH);
        return address(tokemakAutoETHAdapter);
    }

    function _saveDeployment(Adapter adapter, address adapterAddress, address levvaVault) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(path)) {
            _createEmptyDeploymentFile(path);
        }

        string memory deploymentKey = _getAdapterName(adapter);
        if (_isPerVaultAdapter(adapter)) {
            deploymentKey = string.concat(deploymentKey, "_", vm.toString(levvaVault));
        }
        _saveInDeploymentFile(path, deploymentKey, adapterAddress);
    }
}
