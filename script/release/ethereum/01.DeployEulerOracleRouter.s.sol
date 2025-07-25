// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {stdJson} from "forge-std/StdJson.sol";
import {SetupEulerOracleBase} from "../../oracle/SetupEulerOracleBase.sol";
///@dev Deploy factory script
///@dev forge script script/DeployLevvaVaultFactory.s.sol:DeployLevvaVaultFactory -vvvv --account levvaDeployer --rpc-url $ETH_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast

///@dev forge script script/release/ethereum/01.DeployEulerOracleRouter.s.sol:DeployEulerOracleRouter -vvvv --account levvaDeployer --rpc-url $ETH_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast
contract DeployEulerOracleRouter is SetupEulerOracleBase {
    using stdJson for string;

    function run() external {
        _deployEulerRouter();
    }
}
