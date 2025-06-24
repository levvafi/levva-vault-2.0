// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployHelper} from "../helper/DeployHelper.sol";
import {EulerRouter} from "euler-price-oracle/EulerRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PendleUniversalOracle} from "euler-price-oracle/adapter/pendle/PendleUniversalOracle.sol";
import {FixedRateOracle} from "euler-price-oracle/adapter/fixed/FixedRateOracle.sol";
import {CrossAdapter} from "euler-price-oracle/adapter/CrossAdapter.sol";
import {CurveEMAOracle} from "euler-price-oracle/adapter/curve/CurveEMAOracle.sol";
import {IPMarket} from "@pendle/core-v2/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/interfaces/IPPrincipalToken.sol";

///@dev forge script script/oracle/SetupEulerOracle.s.sol:SetupEulerOracle -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract SetupEulerOracle is Script, DeployHelper {
    using stdJson for string;

    EulerRouter private eulerRouter;

    function run() external {
        eulerRouter = EulerRouter(getAddress("EulerOracle"));
        setupUltraSafeVaultOracle();
    }

    function setupUltraSafeVaultOracle() public {
        /**
         * Setup prices for pairs:
         * aUSDC/USDC
         * LP_sUSDE_25Sep2025/USDC
         * LP_wstUSR_25Sep2025/USDC
         * LVVA-sUSDE/USDC (MetaVault sUSDE)
         * LVVA-wstUSR/USDC (MetaVault wstUSR)
         */
        _setupPrice_aUSDC__USDC();
        _setupPrice_LP_sUSDE_25Sep2025__USDE();
        _setupPrice_LP_wstUSR_25Sep2025__USDC();
        //_setupPrice_LVVA_sUSDE__USDC();
        //_setupPrice_LVVA_wstUSR__USDC();
    }

    /// @dev For testing purposes, when  EulerRouter is not deployed yet
    function _deployEulerRouter() private returns (EulerRouter) {
        address oracleGovernor = getAddress("EulerOracleGovernor");

        vm.startBroadcast();
        EulerRouter _eulerRouter = new EulerRouter(address(1), oracleGovernor);
        vm.stopBroadcast();

        console.log("EulerRouter deployed at:", address(_eulerRouter));

        return _eulerRouter;
    }

    function _setupPrice_aUSDC__USDC() private {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");

        _addAave_aUsdc_USDC_price();
        _checkOraclePrice(aUSDC, USDC);
    }

    function _setupPrice_LP_sUSDE_25Sep2025__USDE() private {
        address USDE = getAddress("USDE");
        address USDC = getAddress("USDC");
        address LP_sUSDE_25Sep2025 = getAddress("PendleMarket_sUSDE_25sep2025");

        address lp_sUSDE25Sep2025_USDE_oracle = _addPendleOracle_LP_sUSDE_25Sep2025__USDE();
        _checkOraclePrice(LP_sUSDE_25Sep2025, USDE);

        address USDE_USD_oracle = getAddress("Chainlink_USDE_USD_oracle");
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        address USDE_USDC_oracle = _addCrossOracle(USDE, USD, USDC, USDE_USD_oracle, USDC_USD_oracle);
        _checkOraclePrice(USDE, USDC);

        _addCrossOracle(LP_sUSDE_25Sep2025, USDE, USDC, lp_sUSDE25Sep2025_USDE_oracle, USDE_USDC_oracle);

        _checkOraclePrice(LP_sUSDE_25Sep2025, USDC);
    }

    function _setupPrice_LP_wstUSR_25Sep2025__USDC() private {
        address USR = getAddress("USR");
        address USDC = getAddress("USDC");
        address LP_wstUSR_25Sep2025 = getAddress("PendleMarket_wstUSR_25sep2025");

        address lp_wstUSR_25Sep2025_USR_oracle = _addPendleOracle_LP_wstUSR_25Sep2025__USR();
        _checkOraclePrice(LP_wstUSR_25Sep2025, USR);
        address USR_USDC_oracle = _addCurveEma_USR_USDC();
        _checkOraclePrice(USR, USDC);

        _addCrossOracle(LP_wstUSR_25Sep2025, USR, USDC, lp_wstUSR_25Sep2025_USR_oracle, USR_USDC_oracle);

        _checkOraclePrice(LP_wstUSR_25Sep2025, USDC);
    }

    function _setupPrice_LVVA_sUSDE__USDC() private {
        address sUSDE = getAddress("sUSDE");
        address USDC = getAddress("USDC");
        address LVVA_sUSDE = getAddress("LVVA_sUSDE");

        address sUSDE_USDC_oracle = _getRequiredOracle(sUSDE, USDC);

        address LVVA_sUSDE_sUSDE_oracle = _addResolvedVault_LVVA_sUSDE_sUSDE();

        _addCrossOracle(LVVA_sUSDE, sUSDE, USDC, LVVA_sUSDE_sUSDE_oracle, sUSDE_USDC_oracle);

        _checkOraclePrice(LVVA_sUSDE, USDC);
    }

    function _setupPrice_LVVA_wstUSR__USDC() private {
        address wstUSR = getAddress("WSTUSR");
        address USR = getAddress("USR");
        address USDC = getAddress("USDC");
        address LVVA_wstUSR = getAddress("LVVA_wstUSR");

        address wstUSR_USR_oracle = _addResolvedVault_wstUSR_USR();
        address USR_USDC_oracle = _getRequiredOracle(USR, USDC);

        _addCrossOracle(LVVA_wstUSR, wstUSR, USDC, wstUSR_USR_oracle, USR_USDC_oracle);

        _checkOraclePrice(LVVA_wstUSR, USDC);
    }

    function _addPendleOracle_LP_sUSDE_25Sep2025__USDE() private returns (address) {
        address pendleOracle = getAddress("PendleOracle");
        address LP_sUSDE_25sep2025 = getAddress("PendleMarket_sUSDE_25sep2025");
        address USDE = getAddress("USDE");
        uint32 twapWindow = 5 minutes;

        vm.startBroadcast();
        PendleUniversalOracle pendleUniversalOracle =
            new PendleUniversalOracle(pendleOracle, LP_sUSDE_25sep2025, LP_sUSDE_25sep2025, USDE, twapWindow);
        eulerRouter.govSetConfig(LP_sUSDE_25sep2025, USDE, address(pendleUniversalOracle));

        vm.stopBroadcast();

        return address(pendleUniversalOracle);
    }

    function _addPendleOracle_LP_wstUSR_25Sep2025__USR() private returns (address) {
        address pendleOracle = getAddress("PendleOracle");
        address LP_wstUSR_25sep2025 = getAddress("PendleMarket_wstUSR_25sep2025");
        address USR = getAddress("USR");
        uint32 twapWindow = 5 minutes;

        vm.startBroadcast();
        PendleUniversalOracle pendleUniversalOracle =
            new PendleUniversalOracle(pendleOracle, LP_wstUSR_25sep2025, LP_wstUSR_25sep2025, USR, twapWindow);
        eulerRouter.govSetConfig(LP_wstUSR_25sep2025, USR, address(pendleUniversalOracle));

        vm.stopBroadcast();

        return address(pendleUniversalOracle);
    }

    function _addAave_aUsdc_USDC_price() private returns (address) {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");
        uint256 rate = 1e6; // fixed conversion rate between aUSDC and USDC

        vm.startBroadcast();
        FixedRateOracle aUSDC_USDC_oracle = new FixedRateOracle(aUSDC, USDC, rate);
        eulerRouter.govSetConfig(aUSDC, USDC, address(aUSDC_USDC_oracle));
        vm.stopBroadcast();

        return address(aUSDC_USDC_oracle);
    }

    function _addCrossOracle(
        address base,
        address cross,
        address quote,
        address oracleBaseCross,
        address oracleCrossQuote
    ) private returns (address) {
        vm.startBroadcast();
        CrossAdapter crossOracle = new CrossAdapter(base, cross, quote, oracleBaseCross, oracleCrossQuote);
        eulerRouter.govSetConfig(base, quote, address(crossOracle));
        vm.stopBroadcast();

        return address(crossOracle);
    }

    function _addCurveEma_USR_USDC() private returns (address) {
        address curvePool = getAddress("CurvePool_USR_USDC");
        address baseToken = getAddress("USDC");
        address quoteToken = getAddress("USR");
        uint256 priceOracleIndex = 0; // curve parameter type(uint256).max for price_oracle(), and index for price_oracle(priceOracleIndex)

        vm.startBroadcast();
        CurveEMAOracle oracle = new CurveEMAOracle(curvePool, baseToken, priceOracleIndex);
        eulerRouter.govSetConfig(baseToken, quoteToken, address(oracle));
        vm.stopBroadcast();

        return address(oracle);
    }

    function _addResolvedVault_wstUSR_USR() private returns (address) {
        address wstUSR = getAddress("WSTUSR");
        vm.startBroadcast();
        eulerRouter.govSetResolvedVault(wstUSR, true);
        vm.stopBroadcast();
        return address(eulerRouter);
    }

    function _addResolvedVault_LVVA_sUSDE_sUSDE() private returns (address) {
        address LVVA_sUSDE = getAddress("LVVA_sUSDE");
        vm.startBroadcast();
        eulerRouter.govSetResolvedVault(LVVA_sUSDE, true);
        vm.stopBroadcast();
        return address(eulerRouter);
    }

    function _getOracleConfig(address base, address quote) private view returns (address oracle) {
        return eulerRouter.getConfiguredOracle(base, quote);
    }

    function _getRequiredOracle(address base, address quote) private view returns (address oracle) {
        oracle = _getOracleConfig(base, quote);
        if (oracle == address(0)) {
            revert(string.concat("No oracle configured for pair", ERC20(base).symbol(), "/", ERC20(quote).symbol()));
        }
    }

    function _checkOraclePrice(address base, address quote) private view {
        uint256 inAmount = 1 * 10 ** ERC20(base).decimals();
        uint256 price = eulerRouter.getQuote(inAmount, base, quote);

        string memory baseToken = _getLogTokenName(base);
        string memory quoteToken = _getLogTokenName(quote);

        console.log(string.concat("Oracle price for ", baseToken, "/", quoteToken, " ", vm.toString(price)));
    }

    function _getLogTokenName(address token) private view returns (string memory) {
        ERC20 tokenContract = ERC20(token);
        if (keccak256(abi.encodePacked(tokenContract.name())) == keccak256(abi.encodePacked("Pendle Market"))) {
            (, IPPrincipalToken pt,) = IPMarket(token).readTokens();
            return string.concat("Pendle LP ", pt.symbol());
        } else {
            return tokenContract.symbol();
        }
    }
}
