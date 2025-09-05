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

///@dev forge script script/release/base/02.DeployVaults.s.sol:DeployVaults -vvvv --account levvaDeployer --rpc-url $BASE_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast
contract DeployVaults is LevvaVaultDeployer {
    using stdJson for string;
    using Strings for address;

    function _getDeployConfig() internal view override returns (VaultConfig[] memory configs) {
        if (block.chainid == 8453) {
            configs = new VaultConfig[](1);

            configs[0] = getUltraSafeUSDCVaultConfig();
            configs[1] = getSafeUSDCVaultConfig();
            configs[2] = getBraveUSDCVaultConfig();
            configs[3] = getCustomWETHVaultConfig();
            return configs;
        }

        revert("Config not found for chainId");
    }

    function getUltraSafeUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](2);
        trackedAssets[0] = getAddress("aUSDC");
        trackedAssets[1] = getAddress("sparkUSDC");

        Adapter[] memory adapters = new Adapter[](3);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.UniswapAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaUltraSafeUSDCBase",
            asset: getAddress("USDC"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaUltraSafeUSDCBase",
            lpSymbol: "LUSDCusB",
            withdrawalQueueName: "Withdrawal Voucher LUSDCusB",
            withdrawalQueueSymbol: "WVLUSDCusB",
            trackedAssets: trackedAssets,
            performanceFee: 100_000, // 10%
            managementFee: 0, // 0%
            maxSlippage: 1_000, // 0.1%
            adapters: adapters,
            vaultManager: getAddress("VaultManager"),
            maxExternalPositionAdapters: 15,
            maxTrackedAssets: 15,
            initialDeposit: 1 * 10 ** 6, // 1 USDC minimum deposit
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
            minDepositAmount: 1 * 10 ** 6 // 1 USDC minimum deposit
        });

        return config;
    }

    function getSafeUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](4);
        trackedAssets[0] = getAddress("aUSDC");
        trackedAssets[1] = getAddress("sparkUSDC");
        trackedAssets[2] = getAddress("WETH");
        trackedAssets[3] = getAddress("wrappedSuperOETHb");

        Adapter[] memory adapters = new Adapter[](4);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.UniswapAdapter;
        adapters[3] = Adapter.OriginETHAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaSafeUSDCBase",
            asset: getAddress("USDC"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaSafeUSDCBase",
            lpSymbol: "LUSDCsB",
            withdrawalQueueName: "Withdrawal Voucher LUSDCsB",
            withdrawalQueueSymbol: "WVLUSDCsB",
            trackedAssets: trackedAssets,
            performanceFee: 100_000, // 10%
            managementFee: 0, // 0%
            maxSlippage: 1_000, // 0.1%
            adapters: adapters,
            vaultManager: getAddress("VaultManager"),
            maxExternalPositionAdapters: 15,
            maxTrackedAssets: 15,
            initialDeposit: 1 * 10 ** 6, // 1 USDC minimum deposit
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
            minDepositAmount: 1 * 10 ** 6 // 1 USDC minimum deposit
        });

        return config;
    }

    function getBraveUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](5);
        trackedAssets[0] = getAddress("aUSDC");
        trackedAssets[1] = getAddress("sparkUSDC");
        trackedAssets[2] = getAddress("WETH");
        trackedAssets[3] = getAddress("wrappedSuperOETHb");
        trackedAssets[4] = getAddress("cbBTC");

        Adapter[] memory adapters = new Adapter[](4);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.UniswapAdapter;
        adapters[3] = Adapter.OriginETHAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaBraveUSDCBase",
            asset: getAddress("USDC"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaBraveUSDCBase",
            lpSymbol: "LUSDCbB",
            withdrawalQueueName: "Withdrawal Voucher LUSDCbB",
            withdrawalQueueSymbol: "WVLUSDCbB",
            trackedAssets: trackedAssets,
            performanceFee: 100_000, // 10%
            managementFee: 0, // 0%
            maxSlippage: 1_000, // 0.1%
            adapters: adapters,
            vaultManager: getAddress("VaultManager"),
            maxExternalPositionAdapters: 15,
            maxTrackedAssets: 15,
            initialDeposit: 1 * 10 ** 6, // 1 USDC minimum deposit
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
            minDepositAmount: 1 * 10 ** 6 // 1 USDC minimum deposit
        });

        return config;
    }

    function getCustomWETHVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](1);
        trackedAssets[0] = getAddress("wrappedSuperOETHb");

        Adapter[] memory adapters = new Adapter[](3);
        adapters[0] = Adapter.LevvaPoolAdapter;
        adapters[1] = Adapter.PendleAdapter;
        adapters[2] = Adapter.OriginETHAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaCustomWETHBase",
            asset: getAddress("WETH"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaCustomWETHBase",
            lpSymbol: "LWETHcB",
            withdrawalQueueName: "Withdrawal Voucher for LWETHcB",
            withdrawalQueueSymbol: "WVLWETHcB",
            trackedAssets: trackedAssets,
            performanceFee: 100_000, // 10%
            managementFee: 0, // 0%
            maxSlippage: 1_000, // 0.1%
            adapters: adapters,
            vaultManager: getAddress("VaultManager"),
            maxExternalPositionAdapters: 15,
            maxTrackedAssets: 15,
            initialDeposit: 1 * 10 ** 15, // 0.001 WETH initial deposit
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
            minDepositAmount: 1 * 10 ** 16 // 0.01 WETH minimum deposit
        });

        return config;
    }
}
