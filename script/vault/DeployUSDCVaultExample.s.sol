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
import {ChainValues} from "../helper/ChainValues.sol";
import {Adapter} from "../helper/AdapterUtils.sol";
import {VaultConfig, LevvaVaultDeployer} from "./LevvaVaultDeployer.sol";
import {DeployHelper} from "../helper/DeployHelper.sol";
import {DeployLevvaVaultFactory} from "../DeployLevvaVaultFactory.s.sol";
import {Adapter, DeployAdapter} from "../DeployAdapter.s.sol";

///@dev forge script script/vault/DeployUSDCVaultExample.s.sol:DeployUSDCVaultExample -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract DeployUSDCVaultExample is LevvaVaultDeployer {
    using stdJson for string;
    using Strings for address;

    function _getDeployConfig() internal view override returns (VaultConfig[] memory configs) {
        if (block.chainid == 1) {
            address[] memory trackedAssets = new address[](0);

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
                deploymentId: "USDC-Vault-Example",
                asset: getAddress("USDC"),
                feeCollector: getAddress("FeeCollector"),
                eulerOracle: getAddress("EulerOracle"),
                lpName: "Ultra Safe Levva Vault USDC",
                lpSymbol: "LEVVA-USDC-EXAMPLE",
                withdrawalQueueName: "Ultra Safe Levva Vault USDC Withdrawal Queue",
                withdrawalQueueSymbol: "LEVVA-USDC-EXAMPLE-WITHDRAWAL-QUEUE",
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

            configs = new VaultConfig[](1);
            configs[0] = config;
            return configs;
        }

        revert("Config not found for chainId");
    }
}
