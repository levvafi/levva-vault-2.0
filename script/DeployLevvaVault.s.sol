// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EthereumConstants} from "./Constants.s.sol";
import {DeployHelper} from "./DeployHelper.s.sol";
import {DeployLevvaVaultFactory} from "./DeployLevvaVaultFactory.s.sol";
import {Adapter, DeployAdapter} from "./DeployAdapter.s.sol";
import {AaveAdapter} from "../contracts/adapters/aave/AaveAdapter.sol";
import {CurveRouterAdapter} from "contracts/adapters/curve/CurveRouterAdapter.sol";
import {EthenaAdapter} from "contracts/adapters/ethena/EthenaAdapter.sol";
import {LevvaPoolAdapter} from "contracts/adapters/levvaPool/LevvaPoolAdapter.sol";
import {LevvaVaultAdapter} from "contracts/adapters/levvaVault/LevvaVaultAdapter.sol";
import {LidoAdapter} from "contracts/adapters/lido/LidoAdapter.sol";
import {PendleAdapter} from "contracts/adapters/pendle/PendleAdapter.sol";

struct VaultConfig {
    address asset;
    address feeCollector;
    address eulerOracle;
    string lpName;
    string lpSymbol;
    address[] trackedAssets;
    uint48 performanceFee;
    uint48 managementFee;
    Adapter[] adapters;
    address vaultManager;
    uint24 maxSlippage;
    uint256 initialDeposit;
}

///@dev forge script script/DeployLevvaVault.s.sol:DeployLevvaVault -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract DeployLevvaVault is Script, DeployHelper {
    using stdJson for string;
    using Strings for address;

    string public constant DEPLOYMENT_FILE = "vaults.json";

    function run() external {
        VaultConfig memory deployConfig = _getDeployConfig();

        _beforeDeploy(deployConfig);
        _deployVault(deployConfig);
    }

    ///@dev Check before deploy
    function _beforeDeploy(VaultConfig memory deployConfig) internal view {
        address vault = _getDeployedAddress(deployConfig.lpSymbol);
        if (vault != address(0)) {
            revert(string.concat("Vault ", deployConfig.lpSymbol, " already deployed at", vault.toHexString()));
        }
    }

    ///@dev Deploy and configure vault
    function _deployVault(VaultConfig memory config) internal returns (LevvaVault vault) {
        DeployLevvaVaultFactory factoryDeployer = new DeployLevvaVaultFactory();
        address factoryAddress = factoryDeployer.getOrDeployFactory();
        if (factoryAddress == address(0)) {
            revert("Factory not deployed");
        }

        LevvaVaultFactory factory = LevvaVaultFactory(factoryAddress);

        vm.startBroadcast();
        (address deployedVault,) =
            factory.deployVault(config.asset, config.lpName, config.lpSymbol, config.feeCollector, config.eulerOracle);
        vault = LevvaVault(deployedVault);

        vault.addVaultManager(config.vaultManager, true);
        vault.setMaxSlippage(config.maxSlippage);
        vault.setManagementFeeIR(config.managementFee);
        vault.setPerformanceFeeRatio(config.performanceFee);

        //initial deposit
        if (config.initialDeposit != 0) {
            IERC20(config.asset).approve(address(vault), config.initialDeposit);
            vault.deposit(config.initialDeposit, msg.sender);
        }
        vm.stopBroadcast();
        _saveDeploymentState(vault);

        DeployAdapter adapterDeployer = new DeployAdapter();

        //deploy adapters
        for (uint256 i = 0; i < config.adapters.length; i++) {
            address deployedAdapter;
            if (adapterDeployer.isPerVaultAdapter(config.adapters[i])) {
                //deploy for every vault
                deployedAdapter = adapterDeployer.deployAdapter(config.adapters[i]);
            } else {
                // try to find deployed adapter and add to vault
                deployedAdapter = adapterDeployer.getDeployedAdapter(config.adapters[i]);
                if (deployedAdapter == address(0)) {
                    deployedAdapter = adapterDeployer.deployAdapter(config.adapters[i]);
                }
            }

            vm.broadcast();
            vault.addAdapter(deployedAdapter);
        }

        //configure tracked assets
        for (uint256 i = 0; i < config.trackedAssets.length; i++) {
            vm.broadcast();
            vault.addTrackedAsset(config.trackedAssets[i]);
        }

        return vault;
    }

    function _getDeployedAddress(string memory vaultSymbol) internal view returns (address) {
        return _readAddressFromDeployment(DEPLOYMENT_FILE, vaultSymbol);
    }

    function _saveDeploymentState(LevvaVault vault) internal {
        _saveDeploymentState(vault.symbol(), address(vault));
    }

    function _saveDeploymentState(string memory vaultKey, address vault) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        _saveInDeploymentFile(path, vaultKey, vault);
    }

    function _getDeployConfig() internal view returns (VaultConfig memory) {
        if (block.chainid == 1) {
            address[] memory trackedAssets = new address[](0);

            Adapter[] memory adapters = new Adapter[](4);
            adapters[0] = Adapter.AaveAdapter;
            adapters[1] = Adapter.LevvaVaultAdapter;
            adapters[2] = Adapter.PendleAdapter;
            adapters[3] = Adapter.ResolvAdapter;

            VaultConfig memory config = VaultConfig({
                asset: EthereumConstants.USDC,
                feeCollector: EthereumConstants.FEE_COLLECTOR,
                eulerOracle: EthereumConstants.EULER_ORACLE,
                lpName: "Levva Vault USDC",
                lpSymbol: "LEVVA-USDC-1",
                trackedAssets: trackedAssets,
                performanceFee: 10_000, // 1%
                managementFee: 10_000, // 1%
                adapters: adapters,
                vaultManager: EthereumConstants.VAULT_MANAGER,
                maxSlippage: 0,
                initialDeposit: 0
            });

            return config;
        }

        revert("Config not found for chainId");
    }
}
