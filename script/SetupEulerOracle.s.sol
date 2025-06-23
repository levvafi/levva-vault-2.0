// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployHelper} from "./helper/DeployHelper.sol";
import {EulerRouter} from "euler-price-oracle/EulerRouter.sol";

import {PendleUniversalOracle} from "euler-price-oracle/adapter/pendle/PendleUniversalOracle.sol";
import {FixedRateOracle} from "euler-price-oracle/adapter/fixed/FixedRateOracle.sol";
import {CrossAdapter} from "euler-price-oracle/adapter/CrossAdapter.sol";

///@dev forge script script/DeployEulerPriceOracle.s.sol:DeployEulerPriceOracle -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract SetupEulerOracle is Script, DeployHelper {
    using stdJson for string;

    function run() external {
        address lp_sUSDE25Sep2025_USDE_oracle = addPendleOracle_LP_sUSDE_25Sep2025_USDE();
        address aUSDC_USDC_oracle = addAave_aUsdc_USDC_price();
        address USR_USDC_oracle = addCurveEma_USR_USDC();
        address wstUSR_USR_oracle = addResolvedVault_wstUSR_USR();

        address USDE_USD_oracle = getAddress("Chainlink_USDE_USD_oracle");
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        address USDE_USDC_oracle = 
            addCrossOracle(getAddress("USDE"), USD, getAddress("USDC"), USDE_USD_oracle, USDC_USD_oracle);
    }

    function addPendleOracle_LP_sUSDE_25Sep2025__USDE() public returns (address) {
        address eulerRouter = getAddress("EulerOracle");

        address pendleOracle = getAddress("PendleOracle");
        address pendleMarket = getAddress("PendleMarket");
        address baseToken = getAddress("PendleMarket_sUSDE_25sep2025");
        address quoteToken = getAddress("USDE");
        uint32 twapWindow = 5 minutes;

        vm.startBroadcast();
        PendleUniversalOracle pendleUniversalOracle =
            new PendleUniversalOracle(pendleOracle, pendleMarket, baseToken, quoteToken, twapWindow);
        EulerRouter(eulerRouter).govSetConfig(baseToken, quoteToken, address(pendleUniversalOracle));

        vm.stopBroadcast();

        return address(pendleUniversalOracle);
    }

    function addPendleOracle_LP_wstUSR_25Sep2025__wstUSR() public returns (address) {
        address eulerRouter = getAddress("EulerOracle");

        address pendleOracle = getAddress("PendleOracle");
        address pendleMarket = getAddress("PendleMarket");
        address baseToken = getAddress("PendleMarket_wstUSR_25sep2025");
        address quoteToken = getAddress("WSTUSR");
        uint32 twapWindow = 5 minutes;

        vm.startBroadcast();
        PendleUniversalOracle pendleUniversalOracle =
            new PendleUniversalOracle(pendleOracle, pendleMarket, baseToken, quoteToken, twapWindow);
        EulerRouter(eulerRouter).govSetConfig(baseToken, quoteToken, address(pendleUniversalOracle));

        vm.stopBroadcast();

        return address(pendleUniversalOracle);
    }

    function addAave_aUsdc_USDC_price() public returns (address) {
        address eulerRouter = getAddress("EulerOracle");
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");
        uint256 rate = 1e6; // fixed conversion rate between aUSDC and USDC

        vm.startBroadcast();
        FixedRateOracle aUSDC_USDC_oracle = new FixedRateOracle(aUSDC, USDC, rate);
        EulerRouter(eulerRouter).govSetConfig(aUSDC, USDC, address(aUSDC_USDC_oracle));
        vm.stopBroadcast();

        return address(aUSDC_USDC_oracle);
    }

    function addCrossOracle(
        address base,
        address cross,
        address quote,
        address oracleBaseCross,
        address oracleCrossQuote
    ) public returns (address) {
        address eulerRouter = getAddress("EulerOracle");

        vm.startBroadcast();
        CrossAdapter crossOracle = new CrossAdapter(base, cross, quote, oracleBaseCross, oracleCrossQuote);
        EulerRouter(eulerRouter).govSetConfig(aUSDC, USDC, address(aUSDC_USDC_oracle));
        vm.stopBroadcast();
    }

    function addCurveEma_USR_USDC() public returns (address) {
        address eulerRouter = getAddress("EulerOracle");
        address curvePool = getAddress("CurvePool_USR_USDC");
        address baseToken = getAddress("USDC");
        address quoteToken = getAddress("USR");
        uint256 priceOracleIndex = 0; // curve parameter type(uint256).max for price_oracle(), and index for price_oracle(priceOracleIndex)

        vm.startBroadcast();
        CurveEMAOracle oracle = new CurveEMAOracle(curvePool, baseToken, priceOracleIndex);
        EulerRouter(eulerRouter).govSetConfig(baseToken, quoteToken, address(oracle));
        vm.stopBroadcast();

        return address(oracle);
    }

    function addResolvedVault_wstUSR_USR() public returns (address) {
        address eulerRouter = getAddress("EulerOracle");
        address resolvedVault = getAddress("WSTUSR");
        vm.startBroadcast();
        EulerRouter(eulerRouter).govSetResolvedVault(resolvedVault, true);
        vm.stopBroadcast();

        return eulerRouter;
    }
}
