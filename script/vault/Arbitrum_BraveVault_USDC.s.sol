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

///@dev forge script script/vault/Arbitrum_BraveVault_USDC.s.sol:Arbitrum_BraveVault_USDC -vvvv --account testDeployer --rpc-url $ARB_RPC_URL --broadcast --verify --delay 7 --retries 15 --verifier etherscan --etherscan-api-key $ARBISCAN_KEY --verifier-url https://api.arbiscan.io/api
contract Arbitrum_BraveVault_USDC is LevvaVaultDeployer {
    using stdJson for string;
    using Strings for address;

    function _getDeployConfig() internal view override returns (VaultConfig memory) {
        if (block.chainid == ARBITRUM) {
            address[] memory trackedAssets = new address[](0);

            Adapter[] memory adapters = new Adapter[](7);
            adapters[0] = Adapter.AaveAdapter;
            adapters[1] = Adapter.CurveRouterAdapter;
            adapters[2] = Adapter.LevvaPoolAdapter;
            adapters[3] = Adapter.LevvaVaultAdapter;
            adapters[4] = Adapter.PendleAdapter;
            adapters[5] = Adapter.UniswapAdapter;
            adapters[6] = Adapter.MorphoV1_1;

            VaultConfig memory config = VaultConfig({
                asset: getAddress("USDC"),
                feeCollector: getAddress("FeeCollector"),
                eulerOracle: getAddress("EulerOracle"),
                lpName: "Test Brave Levva Vault USDC",
                lpSymbol: "LVVA-USDC-BRAVE",
                trackedAssets: trackedAssets,
                performanceFee: 10_000, // 1%
                managementFee: 10_000, // 1%
                adapters: adapters,
                vaultManager: getAddress("VaultManager"),
                maxSlippage: 0,
                initialDeposit: 0
            });

            return config;
        }

        revert("Config not found for chainId");
    }
}
