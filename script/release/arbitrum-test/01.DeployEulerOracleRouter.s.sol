// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployHelper} from "../../helper/DeployHelper.sol";
import {EulerRouter} from "euler-price-oracle/EulerRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PendleUniversalOracle} from "euler-price-oracle/adapter/pendle/PendleUniversalOracle.sol";
import {FixedRateOracle} from "euler-price-oracle/adapter/fixed/FixedRateOracle.sol";
import {CrossAdapter} from "euler-price-oracle/adapter/CrossAdapter.sol";
import {CurveEMAOracle} from "euler-price-oracle/adapter/curve/CurveEMAOracle.sol";
import {IPMarket} from "@pendle/core-v2/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/interfaces/IPPrincipalToken.sol";
import {SetupEulerOracleBase} from "../../oracle/SetupEulerOracleBase.sol";

///@dev forge script script/release/arbitrum-test/01.DeployEulerOracleRouter.s.sol:DeployEulerOracleRouter -vvvv --account testDeployer --rpc-url $ARB_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast
contract DeployEulerOracleRouter is SetupEulerOracleBase {
    using stdJson for string;

    function run() external {
        _deployEulerRouter();
    }
}
