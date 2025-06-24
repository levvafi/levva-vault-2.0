// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ChainValues} from "../helper/ChainValues.sol";
import {DeployHelper} from "../helper/DeployHelper.sol";
import {Adapter, AdapterUtils} from "../helper/AdapterUtils.sol";
import {DeployLevvaVaultFactory} from "../DeployLevvaVaultFactory.s.sol";
import {Adapter, DeployAdapter} from "../DeployAdapter.s.sol";

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

abstract contract LevvaVaultDeployer is DeployHelper, AdapterUtils {
    using stdJson for string;

    string public constant DEPLOYMENT_FILE = "vaults.json";

    function run() external virtual {
        VaultConfig memory deployConfig = _getDeployConfig();

        LevvaVault vault = _deployVault(deployConfig);
        _deployAdapters(deployConfig, vault);
        _saveDeploymentState(vault);
    }

    ///@dev Deploy and configure vault
    function _deployVault(VaultConfig memory config) internal returns (LevvaVault vault) {
        //skip deployment if already deployed
        address deployedVault = _getDeployedAddress(config.lpSymbol);
        if (deployedVault != address(0)) {
            return LevvaVault(deployedVault);
        }

        //LevvaVault factory should be deployed first
        LevvaVaultFactory factory = LevvaVaultFactory(getAddress("LevvaVaultFactory"));

        vm.startBroadcast();
        (deployedVault,) =
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

        //configure tracked assets
        for (uint256 i = 0; i < config.trackedAssets.length; ++i) {
            vm.broadcast();
            vault.addTrackedAsset(config.trackedAssets[i]);
        }

        return vault;
    }

    function _deployAdapters(VaultConfig memory config, LevvaVault vault) internal {
        DeployAdapter adapterDeployer = new DeployAdapter();

        for (uint256 i = 0; i < config.adapters.length; ++i) {
            Adapter adapter = config.adapters[i];

            //skip if adapter already connected
            bytes4 adapterId = _getAdapterId(adapter);
            if (address(vault.getAdapter(adapterId)) != address(0)) {
                continue;
            }

            address adapterAddress = adapterDeployer.getOrDeployAdapter(adapter, address(vault));

            vm.broadcast();
            vault.addAdapter(adapterAddress);
        }
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

    function _getDeployConfig() internal view virtual returns (VaultConfig memory);
}
