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

///@dev forge script script/release/arbitrum-test/02.SetupArbitrumOracles.s.sol:SetupArbitrumOracles -vvvv --account testDeployer --rpc-url $ARB_RPC_URL --verify --etherscan-api-key  $ETHERSCAN_KEY --broadcast
contract SetupArbitrumOracles is SetupEulerOracleBase {
    using stdJson for string;

    function run() external {
        eulerRouter = EulerRouter(getAddress("EulerOracle"));
        //_setupPrice_aUSDC__USDC();
        //_setup_WETH_USDC();
        //_setup_WBTC_USDC();
        _setupPrice_PendleLpGUSDC25Dec2025_USDC();
    }

    function _setupPrice_PendleLpGUSDC25Dec2025_USDC() private {
        address PendleLpGUSDC25Dec2025 = getAddress("PendleLpGUSDC18Dec2025");
        address USDC = getAddress("USDC");
        address gUSDC = getAddress("gUSDC");
        uint32 twapWindow = 900; // 15 minutes

        address PendleLpGUSDC25Dec2025_gUSDC_oracle =
            _deployPendleUniversalOracle(PendleLpGUSDC25Dec2025, PendleLpGUSDC25Dec2025, gUSDC, twapWindow);
        address gUSDC_USDC_oracle = _addResolvedVault(gUSDC);

        _deployCrossOracle(PendleLpGUSDC25Dec2025, gUSDC, USDC, PendleLpGUSDC25Dec2025_gUSDC_oracle, gUSDC_USDC_oracle);
    }

    function _setupPrice_aUSDC__USDC() private {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");

        _addAave_aUsdc_USDC_price();
        _checkOraclePrice(aUSDC, USDC);
    }

    function _setup_WETH_USDC() private {
        address WETH = getAddress("WETH");
        address USDC = getAddress("USDC");

        address Chainlink_WETH_USD = _addChainlink_WETH_USD();
        address Chainlink_USDC_USD = _addChainlink_USDC_USD();
        _deployCrossOracle(WETH, USD, USDC, Chainlink_WETH_USD, Chainlink_USDC_USD);

        _checkOraclePrice(WETH, USDC);
    }

    function _setup_WBTC_USDC() private {
        address WBTC = getAddress("WBTC");
        address USDC = getAddress("USDC");

        address Chainlink_WBTC_USD = _addChainlink_WBTC_USD();
        address Chainlink_USDC_USD = _addChainlink_USDC_USD();
        _deployCrossOracle(WBTC, USD, USDC, Chainlink_WBTC_USD, Chainlink_USDC_USD);

        _checkOraclePrice(WBTC, USDC);
    }

    function _addAave_aUsdc_USDC_price() private returns (address) {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");
        uint256 baseDecimals = ERC20(aUSDC).decimals();
        uint256 rate = 10 ** baseDecimals; // fixed conversion rate between aUSDC and USDC

        return _deployFixedRateOracle(aUSDC, USDC, rate);
    }

    function _addChainlink_WETH_USD() private returns (address) {
        address WETH = getAddress("WETH");
        address chainlinkFeed = getAddress("ChainlinkFeed_WETH_USD");
        uint256 maxStaleness = 1 days;

        return _deployChainlinkOracle(WETH, USD, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_WBTC_USD() private returns (address) {
        address WBTC = getAddress("WBTC");
        address chainlinkFeed = getAddress("ChainlinkFeed_WBTC_USD");
        uint256 maxStaleness = 1 days;

        return _deployChainlinkOracle(WBTC, USD, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_USDC_USD() private returns (address) {
        address USDC = getAddress("USDC");
        address chainlinkFeed = getAddress("ChainlinkFeed_USDC_USD");
        uint256 maxStaleness = 1 days;

        return _deployChainlinkOracle(USDC, USD, chainlinkFeed, maxStaleness);
    }
}
