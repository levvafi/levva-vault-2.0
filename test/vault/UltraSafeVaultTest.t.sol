// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IEulerOracleRouter} from "./IEulerOracleRouter.t.sol";
import {IEulerOracleRouterFactory} from "./IEulerOracleRouterFactory.t.sol";
import {FixedRateOracle} from "euler-price-oracle/adapter/fixed/FixedRateOracle.sol";
import {PendleUniversalOracle} from "euler-price-oracle/adapter/pendle/PendleUniversalOracle.sol";
import {CrossAdapter} from "euler-price-oracle/adapter/CrossAdapter.sol";
import {CurveEMAOracle} from "euler-price-oracle/adapter/curve/CurveEMAOracle.sol";

contract UltraSafeVaultTest is Test {
    uint256 public constant FORK_BLOCK = 22515980;
    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    address private EULER_ORACLE_ROUTER_FACTORY = 0x70B3f6F61b7Bf237DF04589DdAA842121072326A;
    address private PENDLE_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;

    /*  USDC Vault
        Stake USDC in Aave                                   34 %
        Buy sUSDe for USDC, stake sUSDe to Pendle pool      16.5%
        Buy/get sUSDe for USDC, stake sUSDe to Levva vault  16.5%
        Buy/get wstUSR, stake wstUSR to Pendle pool         16.5%
        Buy/get wstUSR, stake wstUSR to Levva vault         16.5%
    */

    address private USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private aUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address private PENDLE_MARKET_sUSDE_25sep2025 = 0xA36b60A14A1A5247912584768C6e53E1a269a9F7;
    address private PENDLE_MARKET_wstUSR_25sep2025 = 0x09fA04Aac9c6d1c6131352EE950CD67ecC6d4fB9;
    address private sUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private wstUSR = 0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055;
    address private USR = 0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110;

    address private USD = 0x0000000000000000000000000000000000000348;
    address private sUSDE_USD_oracle = 0xD4fF9D4e0A3E5995A0E040632F34271b2e9c8a42; // Chainlink
    address private USDC_USD_oracle = 0x6213f24332D35519039f2afa7e3BffE105a37d3F; // Chainlink

    address private OWNER = makeAddr("OWNER");

    function setUp() public {
        startHoax(OWNER);
        IEulerOracleRouter router = prepareEulerOracleRouter(OWNER);

        vm.stopPrank();
    }

    function prepareEulerOracleRouter(address owner) private returns (IEulerOracleRouter router) {
        router = IEulerOracleRouter(IEulerOracleRouterFactory(EULER_ORACLE_ROUTER_FACTORY).deploy(owner));

        //aUSDC/USDC oracle
        FixedRateOracle aUSDC_USDC_oracle = new FixedRateOracle(aUSDC, USDC, 1e18);
        router.govSetConfig(aUSDC, USDC, address(aUSDC_USDC_oracle));

        //PENDLE-Market-sUSDe-25Sep2025 / USDC oracle
        PendleUniversalOracle pMarket_sUSDE_sUSDE_oracle = new PendleUniversalOracle(
            PENDLE_ORACLE,
            PENDLE_MARKET_sUSDE_25sep2025, // pendle market
            PENDLE_MARKET_sUSDE_25sep2025, // base token
            sUSDE, // quote token
            5 minutes // twap window
        );

        CrossAdapter USDC_sUSDE_oracle = new CrossAdapter(sUSDE, USD, USDC, sUSDE_USD_oracle, USDC_USD_oracle);
        CrossAdapter pMarket_sUSDe_USDC_oracle = new CrossAdapter(
            PENDLE_MARKET_sUSDE_25sep2025, sUSDE, USDC, address(pMarket_sUSDE_sUSDE_oracle), address(USDC_sUSDE_oracle)
        );

        router.govSetConfig(PENDLE_MARKET_sUSDE_25sep2025, USDC, address(pMarket_sUSDe_USDC_oracle));

        //PENDLE-Market-sUSDe-25Sep2025
        PendleUniversalOracle pMarket_wstUSR_wstUSR_oracle = new PendleUniversalOracle(
            PENDLE_ORACLE,
            PENDLE_MARKET_wstUSR_25sep2025, // pendle market
            PENDLE_MARKET_wstUSR_25sep2025, // base token
            wstUSR, // quote token
            5 minutes // twap window
        );

        router.govSetResolvedVault(wstUSR, true); // setUp price oracle for wstUSR/USR
        CurveEMAOracle USR_USDC_oracle = new CurveEMAOracle(
            0x3eE841F47947FEFbE510366E4bbb49e145484195, // curve pool USR/USDC
            USR, // base
            0 // index of USR in pool
        );
        CrossAdapter USDC_wstUSR_oracle = new CrossAdapter(wstUSR, USR, USDC, address(router), address(USR_USDC_oracle));
        CrossAdapter pMarket_wstUSR_USDC_oracle = new CrossAdapter(
            PENDLE_MARKET_wstUSR_25sep2025,
            wstUSR,
            USDC,
            address(pMarket_wstUSR_wstUSR_oracle),
            address(USDC_wstUSR_oracle)
        );
        router.govSetConfig(PENDLE_MARKET_wstUSR_25sep2025, USDC, address(pMarket_wstUSR_USDC_oracle));
    }
}
