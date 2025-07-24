// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ChainValues} from "../../helper/ChainValues.sol";
import {Adapter} from "../../helper/AdapterUtils.sol";
import {VaultConfig, LevvaVaultDeployer} from "../../vault/LevvaVaultDeployer.sol";

//@dev factory deploy script
//@dev forge script script/DeployLevvaVaultFactory.s.sol:DeployLevvaVaultFactory -vvvv --account testDeployer --rpc-url $ETH_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast
///@dev forge script script/release/ethereum/02.DeployVaults.s.sol:DeployVaults -vvvv --account testDeployer --rpc-url $ETH_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast
contract DeployVaults is LevvaVaultDeployer {
    using stdJson for string;
    using Strings for address;

    function _getDeployConfig() internal view override returns (VaultConfig[] memory configs) {
        if (block.chainid == 1) {
            configs = new VaultConfig[](4);

            configs[0] = getUltraSafeUSDCVaultConfig();
            configs[1] = getSafeUSDCVaultConfig();
            configs[2] = getBraveUSDCVaultConfig();
            configs[3] = getCustomWETHVaultConfig();
            return configs;
        }

        revert("Config not found for chainId");
    }

    function getUltraSafeUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](0);

        Adapter[] memory adapters = new Adapter[](5);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.PendleAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.LevvaVaultAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaUltraSafeUSDC",
            asset: getAddress("USDC"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaUltraSafeUSDC",
            lpSymbol: "LUSDCus",
            withdrawalQueueName: "Withdrawal Voucher LUSDCus",
            withdrawalQueueSymbol: "WVLUSDCus",
            trackedAssets: trackedAssets,
            performanceFee: 100_000, // 10%
            managementFee: 0, // 0%
            maxSlippage: 1_000, // 0.1%
            adapters: adapters,
            vaultManager: getAddress("VaultManager"),
            maxExternalPositionAdapters: 15,
            maxTrackedAssets: 15,
            initialDeposit: 0,
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer")
        });

        return config;
    }

    function getSafeUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](0);

        Adapter[] memory adapters = new Adapter[](5);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.PendleAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.LevvaVaultAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaSafeUSDC",
            asset: getAddress("USDC"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaSafeUSDC",
            lpSymbol: "LUSDCs",
            withdrawalQueueName: "Withdrawal Voucher LUSDCs",
            withdrawalQueueSymbol: "WVLUSDCs",
            trackedAssets: trackedAssets,
            performanceFee: 100_000, // 10%
            managementFee: 0, // 0%
            maxSlippage: 1_000, // 0.1%
            adapters: adapters,
            vaultManager: getAddress("VaultManager"),
            maxExternalPositionAdapters: 15,
            maxTrackedAssets: 15,
            initialDeposit: 0,
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer")
        });

        return config;
    }

    function getBraveUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](0);

        Adapter[] memory adapters = new Adapter[](5);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.PendleAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.LevvaVaultAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaBraveUSDC",
            asset: getAddress("USDC"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaBraveUSDC",
            lpSymbol: "LUSDCb",
            withdrawalQueueName: "Withdrawal Voucher LUSDCb",
            withdrawalQueueSymbol: "WVLUSDCb",
            trackedAssets: trackedAssets,
            performanceFee: 100_000, // 10%
            managementFee: 0, // 0%
            maxSlippage: 1_000, // 0.1%
            adapters: adapters,
            vaultManager: getAddress("VaultManager"),
            maxExternalPositionAdapters: 15,
            maxTrackedAssets: 15,
            initialDeposit: 0,
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer")
        });

        return config;
    }

    function getCustomWETHVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](0);

        Adapter[] memory adapters = new Adapter[](5);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.PendleAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.LevvaVaultAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaCustomWETH",
            asset: getAddress("WETH"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaCustomWETH",
            lpSymbol: "LWETHc",
            withdrawalQueueName: "Withdrawal Voucher for LWETHc",
            withdrawalQueueSymbol: "WVLWETHc",
            trackedAssets: trackedAssets,
            performanceFee: 100_000, // 10%
            managementFee: 0, // 0%
            maxSlippage: 1_000, // 0.1%
            adapters: adapters,
            vaultManager: getAddress("VaultManager"),
            maxExternalPositionAdapters: 15,
            maxTrackedAssets: 15,
            initialDeposit: 0,
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer")
        });

        return config;
    }
}
