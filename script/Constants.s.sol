// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

library EthereumConstants {
    /* Levva vault parameters */
    address public constant LEVVA_VAULT_FACTORY = address(0);
    address public constant EULER_ORACLE = address(1);

    /* Deploy parameters */
    address public constant FEE_COLLECTOR = address(1);
    address public constant VAULT_MANAGER = address(1);

    /* Adapter constants **/
    address public constant AAVE_POOL_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant CURVE_ROUTER_V_1_2 = 0x45312ea0eFf7E09C83CBE249fa1d7598c4C8cd4e;

    /* Tokens */
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant A_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USR = 0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110;
    address public constant WSTUSR = 0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055;
}

library ArbitrumOneConstants {
    /* Adapter constants **/
    address constant AAVE_POOL_ADDRESS_PROVIDER = address(0);

    /* Tokens */
    address constant USDT = address(0);
    address constant A_USDC = address(0);
    address constant USDC = address(0);
    address constant WETH = address(0);
}
