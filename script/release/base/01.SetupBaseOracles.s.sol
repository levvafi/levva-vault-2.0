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

///@dev forge script script/release/base/01.SetupBaseOracles.s.sol:SetupBaseOracles -vvvv --account levvaDeployer --rpc-url $BASE_RPC_URL --verify --etherscan-api-key $ETHERSCAN_KEY --broadcast
contract SetupBaseOracles is SetupEulerOracleBase {
    using stdJson for string;

    function run() external {
        eulerRouter = EulerRouter(getAddress("EulerOracle"));

        _setupPrice_aUSDC__USDC();
        _setupPrice_cbBTC__USDC();
        _setupPrice_WETH__USDC();
        _setupPrice_sparkUSDC__USDC();
        _setupPrice_wrappedSuperOETHb__USDC();
        _setupPrice_morphoSparkUSDC__USDC();
    }

    function _setupPrice_aUSDC__USDC() private {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");

        _addAave_aUsdc_USDC_price();
        _checkOraclePrice(aUSDC, USDC);
    }

    function _setupPrice_cbBTC__USDC() private {
        address CB_BTC = getAddress("cbBTC");
        address USDC = getAddress("USDC");

        address CB_BTC_USD_oracle = getAddress("Chainlink_cbBTC_USD_oracle");
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        _deployCrossOracle(CB_BTC, USD, USDC, CB_BTC_USD_oracle, USDC_USD_oracle);
        _checkOraclePrice(CB_BTC, USDC);
    }

    function _setupPrice_WETH__USDC() private {
        address WETH = getAddress("WETH");
        address USDC = getAddress("USDC");

        address WETH_USD_oracle = getAddress("Chainlink_WETH_USD_oracle");
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        _deployCrossOracle(WETH, USD, USDC, WETH_USD_oracle, USDC_USD_oracle);
        _checkOraclePrice(WETH, USDC);
    }

    function _setupPrice_sparkUSDC__USDC() private {
        address SPARK_USDC = getAddress("sparkUSDC");
        _addResolvedVault(SPARK_USDC);
        _checkOraclePrice(SPARK_USDC, getAddress("USDC"));
    }

    function _setupPrice_morphoSparkUSDC__USDC() private {
        address MORPHO_SPARK_USDC = getAddress("MorphoSparkUSDC");
        _addResolvedVault(MORPHO_SPARK_USDC);
        _checkOraclePrice(MORPHO_SPARK_USDC, getAddress("USDC"));
    }

    function _setupPrice_wrappedSuperOETHb__USDC() private {
        address WRAPPED_SUPER_OETH_B = getAddress("wrappedSuperOETHb");
        _addResolvedVault(WRAPPED_SUPER_OETH_B);

        address SUPER_OETH_B = getAddress("superOETHb");
        _checkOraclePrice(WRAPPED_SUPER_OETH_B, SUPER_OETH_B);

        address WETH = getAddress("WETH");
        address CURVE_POOL_SUPER_OETH_B__WETH = getAddress("CurvePool_superOETHb_WETH");
        address oEthWethOracle = _deployCurveEmaOracle(CURVE_POOL_SUPER_OETH_B__WETH, SUPER_OETH_B, WETH, 0);
        _checkOraclePrice(SUPER_OETH_B, WETH);
        _checkOraclePrice(WRAPPED_SUPER_OETH_B, WETH);

        address wethUsdcOracle = getAddress("CrossOracle_WETH__USDC");
        address USDC = getAddress("USDC");
        _deployCrossOracle(SUPER_OETH_B, WETH, USDC, oEthWethOracle, wethUsdcOracle);
        _checkOraclePrice(WRAPPED_SUPER_OETH_B, USDC);
    }

    function _addAave_aUsdc_USDC_price() private returns (address) {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");
        uint256 baseDecimals = ERC20(aUSDC).decimals();
        uint256 rate = 10 ** baseDecimals; // fixed conversion rate between aUSDC and USDC

        return _deployFixedRateOracle(aUSDC, USDC, rate);
    }
}
