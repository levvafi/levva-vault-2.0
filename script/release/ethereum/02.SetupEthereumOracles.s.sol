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

///@dev forge script script/release/ethereum/02.SetupEthereumOracles.s.sol:SetupEthereumOracles -vvvv --account levvaDeployer --rpc-url $ETH_RPC_URL --verify --etherscan-api-key $ETHERSCAN_KEY --broadcast
contract SetupEthereumOracles is SetupEulerOracleBase {
    using stdJson for string;

    function run() external {
        eulerRouter = EulerRouter(getAddress("EulerOracle"));

        _setupPrice_aUSDC__USDC();
        _setupPrice_sUSDe_USDC();
        _setupPrice_wstUSR_USDC();
        _setupPrice_wstETH_USDC();
        _setupPrice_eBTC_USDC();
        _setupPrice_weETH_WETH();
        _setupPrice_wstETH_WETH();
        _setupPrice_WBTC_USDC();
        _setupPrice_WETH_USDC();
    }

    function _setupPrice_sUSDe_USDC() private {
        address sUSDE = getAddress("sUSDE");
        address USDC = getAddress("USDC");

        // Chainlink sUSDE_USD oracle already deployed by Euler team
        address sUSDE_USD_oracle = getAddress("Chainlink_sUSDE_USD_oracle");
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        _deployCrossOracle(sUSDE, USD, USDC, sUSDE_USD_oracle, USDC_USD_oracle);
    }

    function _setupPrice_wstUSR_USDC() private {
        address wstUSR = getAddress("wstUSR");
        address USDC = getAddress("USDC");
        address USR = getAddress("USR");

        address wstUSR_USR_oracle = _addResolvedVault_wstUSR_USR();
        address USR_USD_oracle = _addChainlink_USR__USD();
        address wstUSR_USD_oracle = _deployCrossOracle(wstUSR, USR, USD, wstUSR_USR_oracle, USR_USD_oracle);

        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");

        _deployCrossOracle(wstUSR, USD, USDC, wstUSR_USD_oracle, USDC_USD_oracle);
    }

    function _setupPrice_wstETH_USDC() private {
        address wstETH = getAddress("wstETH");
        address USDC = getAddress("USDC");
        address WETH = getAddress("WETH");

        address wstETH_WETH_oracle = getAddress("LidoFundamentalOracle");
        address USDC_WETH_oracle = getAddress("Chainlink_USDC_WETH_oracle");

        _deployCrossOracle(wstETH, WETH, USDC, wstETH_WETH_oracle, USDC_WETH_oracle);
    }

    function _setupPrice_wstETH_WETH() private {
        address wstETH = getAddress("wstETH");
        address WETH = getAddress("WETH");
        address lidoFundamentalOracle = getAddress("LidoFundamentalOracle");

        //add lido fundamental oracle into euler router
        vm.startBroadcast();
        eulerRouter.govSetConfig(wstETH, WETH, lidoFundamentalOracle);
        vm.stopBroadcast();
    }

    function _setupPrice_weETH_WETH() private {
        _addChainlink_weETH_ETH();
    }

    function _setupPrice_aUSDC__USDC() private {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");

        _addAave_aUsdc_USDC_price();
        _checkOraclePrice(aUSDC, USDC);
    }

    function _setupPrice_eBTC_USDC() private {
        address eBTC = getAddress("eBTC");
        address USDC = getAddress("USDC");

        address eBTC_USD_oracle = getAddress("CrossChainOracle_eBTC_BTC_USD");
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");

        _deployCrossOracle(eBTC, USD, USDC, eBTC_USD_oracle, USDC_USD_oracle);
    }

    function _setupPrice_WBTC_USDC() private {
        address WBTC = getAddress("WBTC");
        address USDC = getAddress("USDC");

        address WBTC_BTC_oracle = getAddress("Chainlink_WBTC_BTC_oracle");
        address BTC_USD_oracle = getAddress("Chainlink_BTC_USD_oracle");
        address WBTC_USD_oracle = _deployCrossOracle(WBTC, BTC, USD, WBTC_BTC_oracle, BTC_USD_oracle);

        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        _deployCrossOracle(WBTC, USD, USDC, WBTC_USD_oracle, USDC_USD_oracle);
    }

    function _setupPrice_WETH_USDC() private {
        address WETH = getAddress("WETH");
        address USDC = getAddress("USDC");

        address WETH_USD_oracle = getAddress("Chainlink_WETH_USD_oracle");
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        _deployCrossOracle(WETH, USD, USDC, WETH_USD_oracle, USDC_USD_oracle);
    }

    function _addAave_aUsdc_USDC_price() private returns (address) {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");
        uint256 baseDecimals = ERC20(aUSDC).decimals();
        uint256 rate = 10 ** baseDecimals; // fixed conversion rate between aUSDC and USDC

        return _deployFixedRateOracle(aUSDC, USDC, rate);
    }

    function _addChainlink_USR__USD() private returns (address) {
        address USR = getAddress("USR");
        address chainlinkFeed = getAddress("ChainlinkFeed_USR_USD");
        uint256 maxStaleness = 1.5 days;

        return _deployChainlinkOracle(USR, USD, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_weETH_ETH() private returns (address) {
        address weETH = getAddress("weETH");
        address WETH = getAddress("WETH");
        address chainlinkFeed = getAddress("ChainlinkFeed_weETH_ETH");
        uint256 maxStaleness = 1.5 days;

        return _deployChainlinkOracle(weETH, WETH, chainlinkFeed, maxStaleness);
    }

    function _addResolvedVault_wstUSR_USR() private returns (address) {
        address wstUSR = getAddress("wstUSR");

        if (_isResolvedVault(wstUSR)) {
            return address(eulerRouter);
        }

        vm.startBroadcast();
        eulerRouter.govSetResolvedVault(wstUSR, true);
        vm.stopBroadcast();
        return address(eulerRouter);
    }
}
