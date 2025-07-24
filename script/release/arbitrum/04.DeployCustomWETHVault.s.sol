// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ChainValues} from "../../helper/ChainValues.sol";
import {Adapter} from "../../helper/AdapterUtils.sol";
import {VaultConfig, LevvaVaultDeployer} from "../../vault/LevvaVaultDeployer.sol";
import {DeployHelper} from "../../helper/DeployHelper.sol";

///@dev forge script script/release/arbitrum/04.DeployCustomWETHVault.s.sol:DeployCustomWETHVault -vvvv --account testDeployer --rpc-url $ARB_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast
contract DeployCustomWETHVault is LevvaVaultDeployer {
    using stdJson for string;
    using Strings for address;

    function _getDeployConfig() internal view override returns (VaultConfig memory) {
        if (block.chainid == 42161) {
            address[] memory trackedAssets = new address[](0);

            Adapter[] memory adapters = new Adapter[](5);
            adapters[0] = Adapter.AaveAdapter;
            adapters[1] = Adapter.CurveRouterAdapter;
            adapters[2] = Adapter.MorphoV1_1;
            adapters[3] = Adapter.PendleAdapter;
            adapters[4] = Adapter.UniswapAdapter;

            VaultConfig memory config = VaultConfig({
                deploymentId: "LEVVA-ARB-WETH-CUSTOM",
                asset: getAddress("WETH"),
                feeCollector: getAddress("FeeCollector"),
                eulerOracle: getAddress("EulerOracle"),
                lpName: "Custom Levva Vault WETH",
                lpSymbol: "LEVVA-ARB-WETH",
                withdrawalQueueName: "Custom Levva Vault Arb WETH Withdrawal Queue",
                withdrawalQueueSymbol: "LEVVA-ARB-WETH-WITHDRAWAL-QUEUE",
                trackedAssets: trackedAssets,
                performanceFee: 10_000, // 1%
                managementFee: 10_000, // 1%
                adapters: adapters,
                vaultManager: getAddress("VaultManager"),
                maxSlippage: 0,
                maxExternalPositionAdapters: 15,
                maxTrackedAssets: 15,
                initialDeposit: 0,
                withdrawQueueFinalizer: getAddress("WithdrawalQueueFinalizer")
            });

            return config;
        }

        revert("Config not found for chainId");
    }
}
