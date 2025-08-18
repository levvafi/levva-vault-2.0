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

///@dev forge script script/release/ethereum/03.DeployVaults.s.sol:DeployVaults -vvvv --account levvaDeployer --rpc-url $ETH_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast
contract DeployVaults is LevvaVaultDeployer {
    using stdJson for string;
    using Strings for address;

    function _getDeployConfig() internal view override returns (VaultConfig[] memory configs) {
        if (block.chainid == 1) {
            configs = new VaultConfig[](1);

            configs[0] = getTestUSDCVaultConfig();
            //configs[1] = getSafeUSDCVaultConfig();
            //configs[2] = getBraveUSDCVaultConfig();
            //configs[3] = getCustomWETHVaultConfig();
            return configs;
        }

        revert("Config not found for chainId");
    }

    function getTestUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](5);
        trackedAssets[0] = getAddress("aUSDC");
        trackedAssets[1] = getAddress("sUSDE");
        trackedAssets[2] = getAddress("wstUSR");
        trackedAssets[3] = getAddress("wstETH");
        trackedAssets[4] = getAddress("eBTC");

        Adapter[] memory adapters = new Adapter[](14);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.EthenaAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.EtherfiETH;
        adapters[5] = Adapter.LevvaPoolAdapter;
        adapters[6] = Adapter.LevvaVaultAdapter;
        adapters[7] = Adapter.Lido;
        adapters[8] = Adapter.MakerDaoDAI;
        adapters[9] = Adapter.MakerDaoUSDS;
        adapters[10] = Adapter.Morpho;
        adapters[11] = Adapter.MorphoV1_1;
        adapters[12] = Adapter.PendleAdapter;
        adapters[13] = Adapter.ResolvAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaTestUSDC",
            asset: getAddress("USDC"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaTestUSDC",
            lpSymbol: "LT-USDC",
            withdrawalQueueName: "Withdrawal Voucher LT-USDC",
            withdrawalQueueSymbol: "WVLUSDC",
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

    function getUltraSafeUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](3);
        trackedAssets[0] = getAddress("aUSDC");
        trackedAssets[1] = getAddress("sUSDE");
        trackedAssets[2] = getAddress("wstUSR");

        Adapter[] memory adapters = new Adapter[](14);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.EthenaAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.EtherfiETH;
        adapters[5] = Adapter.LevvaPoolAdapter;
        adapters[6] = Adapter.LevvaVaultAdapter;
        adapters[7] = Adapter.Lido;
        adapters[8] = Adapter.MakerDaoDAI;
        adapters[9] = Adapter.MakerDaoUSDS;
        adapters[10] = Adapter.Morpho;
        adapters[11] = Adapter.MorphoV1_1;
        adapters[12] = Adapter.PendleAdapter;
        adapters[13] = Adapter.ResolvAdapter;

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
            initialDeposit: 1 * 10 ** 6, // 1 USDC minimum deposit
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
            minDepositAmount: 1 * 10 ** 6 // 1 USDC minimum deposit
        });

        return config;
    }

    function getSafeUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](4);
        trackedAssets[0] = getAddress("aUSDC");
        trackedAssets[1] = getAddress("sUSDE");
        trackedAssets[2] = getAddress("wstUSR");
        trackedAssets[3] = getAddress("wstETH");

        Adapter[] memory adapters = new Adapter[](14);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.EthenaAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.EtherfiETH;
        adapters[5] = Adapter.LevvaPoolAdapter;
        adapters[6] = Adapter.LevvaVaultAdapter;
        adapters[7] = Adapter.Lido;
        adapters[8] = Adapter.MakerDaoDAI;
        adapters[9] = Adapter.MakerDaoUSDS;
        adapters[10] = Adapter.Morpho;
        adapters[11] = Adapter.MorphoV1_1;
        adapters[12] = Adapter.PendleAdapter;
        adapters[13] = Adapter.ResolvAdapter;

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
            initialDeposit: 1 * 10 ** 6, // 1 USDC minimum deposit
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
            minDepositAmount: 1 * 10 ** 6 // 1 USDC minimum deposit
        });

        return config;
    }

    function getBraveUSDCVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](5);
        trackedAssets[0] = getAddress("aUSDC");
        trackedAssets[1] = getAddress("sUSDE");
        trackedAssets[2] = getAddress("wstUSR");
        trackedAssets[3] = getAddress("wstETH");
        trackedAssets[4] = getAddress("eBTC");

        Adapter[] memory adapters = new Adapter[](15);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.EthenaAdapter;
        adapters[3] = Adapter.EtherfiBTC;
        adapters[4] = Adapter.EtherfiETH;
        adapters[5] = Adapter.LevvaPoolAdapter;
        adapters[6] = Adapter.LevvaVaultAdapter;
        adapters[7] = Adapter.Lido;
        adapters[8] = Adapter.MakerDaoDAI;
        adapters[9] = Adapter.MakerDaoUSDS;
        adapters[10] = Adapter.Morpho;
        adapters[11] = Adapter.MorphoV1_1;
        adapters[12] = Adapter.PendleAdapter;
        adapters[13] = Adapter.ResolvAdapter;
        adapters[14] = Adapter.UniswapAdapter;

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
            initialDeposit: 1 * 10 ** 6, // 1 USDC minimum deposit
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
            minDepositAmount: 1 * 10 ** 6 // 1 USDC minimum deposit
        });

        return config;
    }

    function getCustomWETHVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](2);
        trackedAssets[0] = getAddress("weETH");
        trackedAssets[1] = getAddress("wstETH");

        Adapter[] memory adapters = new Adapter[](15);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.EthenaAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.EtherfiETH;
        adapters[5] = Adapter.LevvaPoolAdapter;
        adapters[6] = Adapter.LevvaVaultAdapter;
        adapters[7] = Adapter.Lido;
        adapters[8] = Adapter.MakerDaoDAI;
        adapters[9] = Adapter.MakerDaoUSDS;
        adapters[10] = Adapter.Morpho;
        adapters[11] = Adapter.MorphoV1_1;
        adapters[12] = Adapter.PendleAdapter;
        adapters[13] = Adapter.ResolvAdapter;

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
            initialDeposit: 1 * 10 ** 15, // 0.001 WETH initial deposit
            withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer"),
            minDepositAmount: 1 * 10 ** 16 // 0.01 WETH minimum deposit
        });

        return config;
    }

    function getCustomOriginWETHVaultConfig() internal view returns (VaultConfig memory) {
        address[] memory trackedAssets = new address[](4);
        trackedAssets[0] = getAddress("weETH");
        trackedAssets[1] = getAddress("wstETH");
        trackedAssets[2] = getAddress("OETH");
        trackedAssets[3] = getAddress("PendleLPwOETH25Dec2025");

        Adapter[] memory adapters = new Adapter[](14);
        adapters[0] = Adapter.AaveAdapter;
        adapters[1] = Adapter.CurveRouterAdapter;
        adapters[2] = Adapter.EthenaAdapter;
        adapters[3] = Adapter.UniswapAdapter;
        adapters[4] = Adapter.EtherfiETH;
        adapters[5] = Adapter.LevvaPoolAdapter;
        adapters[6] = Adapter.LevvaVaultAdapter;
        adapters[7] = Adapter.Lido;
        adapters[8] = Adapter.MakerDaoDAI;
        adapters[9] = Adapter.MakerDaoUSDS;
        adapters[10] = Adapter.Morpho;
        adapters[11] = Adapter.MorphoV1_1;
        adapters[12] = Adapter.PendleAdapter;
        adapters[13] = Adapter.ResolvAdapter;

        VaultConfig memory config = VaultConfig({
            deploymentId: "LevvaOriginWETH",
            asset: getAddress("WETH"),
            feeCollector: getAddress("FeeCollector"),
            eulerOracle: getAddress("EulerOracle"),
            lpName: "LevvaOriginWETH",
            lpSymbol: "LWETHo",
            withdrawalQueueName: "Withdrawal Voucher for LWETHo",
            withdrawalQueueSymbol: "WVLWETHo",
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
