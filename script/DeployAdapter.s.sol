// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EthereumConstants} from "./Constants.s.sol";
import {DeployHelper} from "./DeployHelper.s.sol";
import {AaveAdapter} from "contracts/adapters/aave/AaveAdapter.sol";
import {CurveRouterAdapter} from "contracts/adapters/curve/CurveRouterAdapter.sol";
import {EthenaAdapter} from "contracts/adapters/ethena/EthenaAdapter.sol";
import {LevvaPoolAdapter} from "contracts/adapters/levvaPool/LevvaPoolAdapter.sol";
import {LevvaVaultAdapter} from "contracts/adapters/levvaVault/LevvaVaultAdapter.sol";
import {LidoAdapter} from "contracts/adapters/lido/LidoAdapter.sol";
import {PendleAdapter} from "contracts/adapters/pendle/PendleAdapter.sol";
import {ResolvAdapter} from "contracts/adapters/resolv/ResolvAdapter.sol";

enum Adapter {
    AaveAdapter,
    CurveRouterAdapter,
    EthenaAdapter,
    EtherfiETH,
    EtherfiBTC,
    LevvaPoolAdapter,
    LevvaVaultAdapter,
    Lido,
    MakerDaoDAI,
    MakerDaoUSDS,
    Morpho,
    MorphoV_1,
    PendleAdapter,
    ResolvAdapter,
    UniswapAdapter
}

///@dev forge script script/DeployAdapter.s.sol:DeployAdapter -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract DeployAdapter is DeployHelper {
    using stdJson for string;
    using Strings for address;

    string public constant DEPLOYMENT_FILE = "adapters.json";

    function run() public {
        //deployAdapter(Adapter.AaveAdapter);
        //deployAdapter(Adapter.ResolvAdapter);
    }

    function isPerVaultAdapter(Adapter adapter) public pure returns (bool) {
        return adapter == Adapter.EthenaAdapter || adapter == Adapter.LevvaPoolAdapter || adapter == Adapter.EtherfiBTC;
    }

    function getDeployedAdapter(Adapter adapter) public view returns (address) {
        string memory valueKey = _getDeploymentKey(adapter);
        return _readAddressFromDeployment(DEPLOYMENT_FILE, valueKey);
    }

    function deployAdapter(Adapter adapter) public returns (address deployedAdapter) {
        if (adapter == Adapter.AaveAdapter) {
            deployedAdapter = _deployAave();
        } else if (adapter == Adapter.CurveRouterAdapter) {
            deployedAdapter = _deployCurve();
        } else if (adapter == Adapter.ResolvAdapter) {
            deployedAdapter = _deployResolv();
        } else if (adapter == Adapter.LevvaVaultAdapter) {
            deployedAdapter = _deployLevvaVault();
        }

        if (deployedAdapter == address(0)) {
            revert("Adapter not supported");
        }

        if (!isPerVaultAdapter(adapter)) {
            _saveDeployment(adapter, deployedAdapter);
        }
    }

    function _deployAave() internal returns (address) {
        vm.broadcast();
        AaveAdapter aaveAdapter = new AaveAdapter(_getAavePoolAddressProvider());
        return address(aaveAdapter);
    }

    function _deployResolv() internal returns (address) {
        vm.broadcast();
        ResolvAdapter resolvAdapter = new ResolvAdapter(_getResolvWstUSR());
        return address(resolvAdapter);
    }

    function _deployCurve() internal returns (address) {
        vm.broadcast();
        CurveRouterAdapter curveAdapter = new CurveRouterAdapter(_getCurveRouter());
        return address(curveAdapter);
    }

    function _deployLevvaVault() internal returns (address) {
        address levvaVaultFactory = _getLevvaVaultFactory();

        vm.broadcast();
        LevvaVaultAdapter levvaVaultAdapter = new LevvaVaultAdapter(levvaVaultFactory);
        return address(levvaVaultAdapter);
    }

    function _saveDeployment(Adapter adapter, address adapterAddress) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(path)) {
            _createEmptyDeploymentFile(path);
        }

        string memory adapterKey = _getDeploymentKey(adapter);
        _saveInDeploymentFile(path, adapterKey, adapterAddress);
    }

    function _getDeploymentKey(Adapter adapter) private pure returns (string memory) {
        if (adapter == Adapter.AaveAdapter) {
            return "AaveAdapter";
        } else if (adapter == Adapter.CurveRouterAdapter) {
            return "CurveRouterAdapter";
        } else if (adapter == Adapter.EthenaAdapter) {
            return "EthenaAdapter";
        } else if (adapter == Adapter.EtherfiETH) {
            return "EtherfiETH";
        } else if (adapter == Adapter.EtherfiBTC) {
            return "EtherfiBTC";
        } else if (adapter == Adapter.LevvaPoolAdapter) {
            return "LevvaPoolAdapter";
        } else if (adapter == Adapter.LevvaVaultAdapter) {
            return "LevvaVaultAdapter";
        } else if (adapter == Adapter.Lido) {
            return "LidoAdapter";
        } else if (adapter == Adapter.MakerDaoDAI) {
            return "MakerDaoDAIAdapter";
        } else if (adapter == Adapter.MakerDaoUSDS) {
            return "MakerDaoUSDSAdapter";
        } else if (adapter == Adapter.Morpho) {
            return "MorphoAdapter";
        } else if (adapter == Adapter.MorphoV_1) {
            return "MorphoAdapterV_1";
        } else if (adapter == Adapter.PendleAdapter) {
            return "PendleAdapter";
        } else if (adapter == Adapter.ResolvAdapter) {
            return "ResolvAdapter";
        } else if (adapter == Adapter.UniswapAdapter) {
            return "UniswapAdapter";
        }

        revert("Adapter not supported");
    }

    function _getAavePoolAddressProvider() private view returns (address) {
        if (block.chainid == 1) {
            return EthereumConstants.AAVE_POOL_ADDRESS_PROVIDER;
        }

        revert("Not supported chainId");
    }

    function _getResolvWstUSR() private view returns (address) {
        if (block.chainid == 1) {
            return EthereumConstants.WSTUSR;
        }

        revert("Not supported chainId");
    }

    function _getCurveRouter() private view returns (address) {
        if (block.chainid == 1) {
            return EthereumConstants.CURVE_ROUTER_V_1_2;
        }

        revert("Not supported chainId");
    }

    function _getLevvaVaultFactory() private view returns (address) {
        if (block.chainid == 1) {
            DeployLevvaVaultFactory factoryDeployer = new DeployLevvaVaultFactory();
            return factoryDeployer.getDeployedFactoryAddress();

            //return EthereumConstants.LEVVA_VAULT_FACTORY;
        }
        revert("Not supported chainId");
    }
}
