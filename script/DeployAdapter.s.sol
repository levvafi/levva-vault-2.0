// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ChainValues} from "./helper/ChainValues.sol";
import {DeployHelper} from "./helper/DeployHelper.sol";
import {AaveAdapter} from "contracts/adapters/aave/AaveAdapter.sol";
import {CurveRouterAdapter} from "contracts/adapters/curve/CurveRouterAdapter.sol";
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
import {DeployLevvaVaultFactory} from "./DeployLevvaVaultFactory.s.sol";
import {Adapter, AdaptersLib} from "./helper/AdaptersLib.sol";

/**
 * @dev Uncomment lines you want to deploy
 * @dev source .env && forge script script/DeployAdapter.s.sol:DeployAdapter -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
 */
contract DeployAdapter is DeployHelper {
    using stdJson for string;
    using Strings for address;
    using AdaptersLib for Adapter;

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
    }

    function getDeployedAdapter(Adapter adapter, address vault) public view returns (address) {
        string memory deploymentKey = adapter.getAdapterName();
        if (adapter.isPerVaultAdapter()) {
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

    function deployAdapter(Adapter adapter, address levvaVault) public returns (address deployedAdapter) {
        if (adapter == Adapter.AaveAdapter) {
            deployedAdapter = _deployAave();
        } else if (adapter == Adapter.CurveRouterAdapter) {
            deployedAdapter = _deployCurve();
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
        address wstUSR = getAddress("WSTUSR");

        vm.broadcast();
        ResolvAdapter resolvAdapter = new ResolvAdapter(wstUSR);
        return address(resolvAdapter);
    }

    function _deployCurve() internal returns (address) {
        address curveRouter = getAddress("CurveRouterV1_2");

        vm.broadcast();
        CurveRouterAdapter curveAdapter = new CurveRouterAdapter(curveRouter);
        return address(curveAdapter);
    }

    function _deployEthena(address levvaVault) internal returns (address) {
        address sUsde = getAddress("sUSDE");

        vm.broadcast();
        EthenaAdapter curveAdapter = new EthenaAdapter(levvaVault, sUsde);
        return address(curveAdapter);
    }

    function _deployEtherfiETH() internal returns (address) {
        address weth = getAddress("WETH");
        address weeth = getAddress("WEETH");
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
        address wsteth = getAddress("WSTETH");
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

    function _saveDeployment(Adapter adapter, address adapterAddress, address levvaVault) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(path)) {
            _createEmptyDeploymentFile(path);
        }

        string memory deploymentKey = adapter.getAdapterName();
        if (adapter.isPerVaultAdapter()) {
            deploymentKey = string.concat(deploymentKey, "_", vm.toString(levvaVault));
        }
        _saveInDeploymentFile(path, deploymentKey, adapterAddress);
    }
}
