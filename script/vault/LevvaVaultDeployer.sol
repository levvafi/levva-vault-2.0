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
    string deploymentId;
    address asset;
    address feeCollector;
    address eulerOracle;
    string lpName;
    string lpSymbol;
    string withdrawalQueueName;
    string withdrawalQueueSymbol;
    address[] trackedAssets;
    uint48 performanceFee;
    uint48 managementFee;
    Adapter[] adapters;
    address vaultManager;
    uint24 maxSlippage;
    uint8 maxExternalPositionAdapters;
    uint8 maxTrackedAssets;
    uint256 initialDeposit;
    address withdrawQueueFinalizer;
    uint256 minDepositAmount;
}

abstract contract LevvaVaultDeployer is DeployHelper, AdapterUtils {
    using stdJson for string;

    string public constant DEPLOYMENT_FILE = "vaults.json";

    function run() external virtual {
        VaultConfig[] memory deployConfigs = _getDeployConfig();

        for (uint256 i = 0; i < deployConfigs.length; i++) {
            VaultConfig memory deployConfig = deployConfigs[i];

            LevvaVault vault = _deployVault(deployConfig);
            _deployAdapters(deployConfig, vault);

            // check
            uint256 totalAssets = vault.totalAssets();
            uint256 totalSupply = vault.totalSupply();
            if (deployConfig.initialDeposit != 0) {
                assert(totalAssets == deployConfig.initialDeposit);
                assert(totalSupply == deployConfig.initialDeposit);
            }

            _saveDeploymentState(deployConfig, address(vault));
        }
    }

    ///@dev Deploy and configure vault
    function _deployVault(VaultConfig memory config) internal returns (LevvaVault vault) {
        //LevvaVault factory should be deployed first
        LevvaVaultFactory factory = LevvaVaultFactory(getAddress("LevvaVaultFactory"));

        //skip deployment if already deployed
        address deployedVault = _getDeployedAddress(config.deploymentId);
        if (deployedVault == address(0)) {
            vm.broadcast();
            (deployedVault,) = factory.deployVault(
                config.asset,
                config.lpName,
                config.lpSymbol,
                config.withdrawalQueueName,
                config.withdrawalQueueSymbol,
                config.feeCollector,
                config.eulerOracle
            );
        }

        vault = LevvaVault(deployedVault);

        if (!vault.isVaultManager(config.vaultManager)) {
            vm.broadcast();
            vault.addVaultManager(config.vaultManager, true);
        }

        if (vault.maxSlippage() != config.maxSlippage) {
            vm.broadcast();
            vault.setMaxSlippage(config.maxSlippage);
        }

        if (vault.maxExternalPositionAdapters() != config.maxExternalPositionAdapters) {
            vm.broadcast();
            vault.setMaxExternalPositionAdapters(config.maxExternalPositionAdapters);
        }

        if (vault.maxTrackedAssets() != config.maxTrackedAssets) {
            vm.broadcast();
            vault.setMaxTrackedAssets(config.maxTrackedAssets);
        }

        // if (config.managementFee != 0) {
        //     vm.broadcast();
        //     vault.setManagementFeeIR(config.managementFee);
        // }

        // if (config.performanceFee != 0) {
        //     vm.broadcast();
        //     vault.setPerformanceFeeRatio(config.performanceFee);
        // }

        WithdrawalQueue withdrawalQueue = WithdrawalQueue(vault.withdrawalQueue());
        if (!withdrawalQueue.isFinalizer(config.withdrawQueueFinalizer)) {
            vm.broadcast();
            withdrawalQueue.addFinalizer(config.withdrawQueueFinalizer, true);
        }

        //initial deposit
        if (config.initialDeposit != 0 && vault.totalAssets() == 0) {
            vm.broadcast();
            IERC20(config.asset).approve(address(vault), config.initialDeposit);
            vm.broadcast();
            vault.deposit(config.initialDeposit, msg.sender);
        }

        if (vault.minimalDeposit() != config.minDepositAmount) {
            vm.broadcast();
            vault.setMinimalDeposit(config.minDepositAmount);
        }

        //configure tracked assets
        for (uint256 i = 0; i < config.trackedAssets.length; ++i) {
            if (vault.trackedAssetPosition(config.trackedAssets[i]) == 0) {
                vm.broadcast();
                vault.addTrackedAsset(config.trackedAssets[i]);
            }
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

    function _getDeployedAddress(string memory deploymentId) internal view returns (address) {
        return _readAddressFromDeployment(DEPLOYMENT_FILE, deploymentId);
    }

    function _saveDeploymentState(VaultConfig memory config, address vault) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        _saveInDeploymentFile(path, config.deploymentId, vault);
    }

    function _getDeployConfig() internal view virtual returns (VaultConfig[] memory);
}
