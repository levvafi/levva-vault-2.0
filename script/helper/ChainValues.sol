// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AddressToBytes32Lib} from "./AddressToBytes32Lib.sol";

contract ChainValues {
    using AddressToBytes32Lib for address;
    using AddressToBytes32Lib for bytes32;

    uint256 public constant ETHEREUM = 1;
    uint256 public constant ARBITRUM = 42161;
    uint256 public constant LOCALHOST = 31337;
    uint256 public constant ETH_HOODIE = 560048;

    address public constant USD = 0x0000000000000000000000000000000000000348;

    mapping(string chainName => mapping(string valueName => bytes32 value)) private s_values;

    error ChainValues__ZeroAddress(string chainName, string valueName);
    error ChainValues__ZeroBytes32(string chainName, string valueName);
    error ChainValues__ValueAlreadySet(string chainName, string valueName);

    constructor() {
        _addEthMainnetValues();
        _addLocalhost();
        _addEthHoodie();
        _addArbitrum();
    }

    function getChainName() public view returns (string memory) {
        if (block.chainid == ETHEREUM) {
            return "ethereum";
        } else if (block.chainid == ARBITRUM) {
            return "arbitrum";
        }
        /*  Test chains */
        else if (block.chainid == LOCALHOST) {
            return "localhost";
        } else if (block.chainid == ETH_HOODIE) {
            return "ethHoodie";
        }

        revert("Not supported chainId");
    }

    function getAddress(string memory valueName) public view returns (address a) {
        a = getAddress(getChainName(), valueName);
    }

    function getAddress(string memory chainName, string memory valueName) public view returns (address a) {
        a = s_values[chainName][valueName].toAddress();
        if (a == address(0)) {
            revert ChainValues__ZeroAddress(chainName, valueName);
        }
    }

    function getERC20(string memory valueName) public view returns (ERC20 erc20) {
        erc20 = getERC20(getChainName(), valueName);
    }

    function getERC20(string memory chainName, string memory valueName) public view returns (ERC20 erc20) {
        address a = getAddress(chainName, valueName);
        erc20 = ERC20(a);
    }

    function getBytes32(string memory valueName) public view returns (bytes32 b) {
        b = getBytes32(getChainName(), valueName);
    }

    function getBytes32(string memory chainName, string memory valueName) public view returns (bytes32 b) {
        b = s_values[chainName][valueName];
        if (b == bytes32(0)) {
            revert ChainValues__ZeroBytes32(chainName, valueName);
        }
    }

    function setValue(bool overrideOk, string memory valueName, bytes32 value) public {
        setValue(overrideOk, getChainName(), valueName, value);
    }

    function setValue(bool overrideOk, string memory chainName, string memory valueName, bytes32 value) public {
        if (!overrideOk && s_values[chainName][valueName] != bytes32(0)) {
            revert ChainValues__ValueAlreadySet(chainName, valueName);
        }
        s_values[chainName][valueName] = value;
    }

    function setAddress(bool overrideOk, string memory valueName, address value) public {
        setAddress(overrideOk, getChainName(), valueName, value);
    }

    function setAddress(bool overrideOk, string memory chainName, string memory valueName, address value) public {
        setValue(overrideOk, chainName, valueName, value.toBytes32());
    }

    function _addEthMainnetValues() private {
        /* ============ LEVVA VAULTS ========== */
        s_values["ethereum"]["LevvaVaultFactory"] = 0xB97b6282633491c9AB3f144796dB6EaA33b610f4.toBytes32();
        s_values["ethereum"]["EulerOracle"] = 0x41761684ACf90bbF7e58e3A7A14d48f778CBB9D5.toBytes32();
        s_values["ethereum"]["FeeCollector"] = 0xD20092A19e0488E1283E488e11583B43ba7EA849.toBytes32();
        s_values["ethereum"]["VaultManager"] = 0x3a57D60a6866c41365E91b9cAbFA66F8Dd17F210.toBytes32();
        s_values["ethereum"]["WithdrawalQueueFinalizer"] = 0x3a57D60a6866c41365E91b9cAbFA66F8Dd17F210.toBytes32();

        /* =========== TOKENS ================ */
        s_values["ethereum"]["aUSDC"] = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c.toBytes32();
        s_values["ethereum"]["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F.toBytes32();
        s_values["ethereum"]["eBTC"] = 0x657e8C867D8B37dCC18fA4Caead9C45EB088C642.toBytes32();
        s_values["ethereum"]["sDAI"] = 0x83F20F44975D03b1b09e64809B757c47f942BEeA.toBytes32();
        s_values["ethereum"]["sUSDE"] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497.toBytes32();
        s_values["ethereum"]["sUSDS"] = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD.toBytes32();
        s_values["ethereum"]["USDS"] = 0xdC035D45d973E3EC169d2276DDab16f1e407384F.toBytes32();
        s_values["ethereum"]["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7.toBytes32();
        s_values["ethereum"]["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48.toBytes32();
        s_values["ethereum"]["USDE"] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3.toBytes32();
        s_values["ethereum"]["USR"] = 0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110.toBytes32();
        s_values["ethereum"]["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2.toBytes32();
        s_values["ethereum"]["wstUSR"] = 0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055.toBytes32();
        s_values["ethereum"]["wstETH"] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0.toBytes32();
        s_values["ethereum"]["weETH"] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee.toBytes32();
        s_values["ethereum"]["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599.toBytes32();

        /* ============== AAVE ================ */
        s_values["ethereum"]["AavePoolAddressProvider"] = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e.toBytes32();

        /* ============== CURVE ================ */
        s_values["ethereum"]["CurveRouterV1_2"] = 0x45312ea0eFf7E09C83CBE249fa1d7598c4C8cd4e.toBytes32();

        /* ============== EtherFi ================ */
        s_values["ethereum"]["EtherFiLiquidityPool"] = 0x308861A430be4cce5502d0A12724771Fc6DaF216.toBytes32();
        s_values["ethereum"]["EtherFiBtcTeller"] = 0x6Ee3aaCcf9f2321E49063C4F8da775DdBd407268.toBytes32();
        s_values["ethereum"]["EtherFiBtcAtomicQueue"] = 0xD45884B592E316eB816199615A95C182F75dea07.toBytes32();

        /* ============== LIDO ================ */
        s_values["ethereum"]["LidoWithdrawalQueue"] = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1.toBytes32();

        /* ============== MORPHO ================ */
        s_values["ethereum"]["MetaMorphoFactory"] = 0xA9c3D3a366466Fa809d1Ae982Fb2c46E5fC41101.toBytes32();
        s_values["ethereum"]["MetaMorphoFactoryV1_1"] = 0x1897A8997241C1cD4bD0698647e4EB7213535c24.toBytes32();

        /* ============== PENDLE =============== */
        s_values["ethereum"]["PendleRouter"] = 0x888888888889758F76e7103c6CbF23ABbF58F946.toBytes32();

        /* ============== UNISWAP =============== */
        s_values["ethereum"]["UniswapV3Router"] = 0xE592427A0AEce92De3Edee1F18E0157C05861564.toBytes32();
        s_values["ethereum"]["UniversalRouter"] = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af.toBytes32();
        s_values["ethereum"]["UniswapPermit2"] = 0x000000000022D473030F116dDEE9F6B43aC78BA3.toBytes32();

        /* ============= PRICE ORACLES ============ */
        s_values["ethereum"]["EulerOracleGovernor"] = 0x0562F16415fCf6fb5ACAF433e4796f8f328b7C7d.toBytes32();
        s_values["ethereum"]["EulerOracleFactory"] = 0x70B3f6F61b7Bf237DF04589DdAA842121072326A.toBytes32();
        s_values["ethereum"]["PendleOracle"] = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2.toBytes32();

        s_values["ethereum"]["PendleMarket_sUSDE_25sep2025"] = 0xA36b60A14A1A5247912584768C6e53E1a269a9F7.toBytes32();
        s_values["ethereum"]["PendleMarket_wstUSR_25sep2025"] = 0x09fA04Aac9c6d1c6131352EE950CD67ecC6d4fB9.toBytes32();
        s_values["ethereum"]["CurvePool_USR_USDC"] = 0x3eE841F47947FEFbE510366E4bbb49e145484195.toBytes32();

        /* ============= DEPLOYED EULER ORACLES ========== */
        s_values["ethereum"]["Chainlink_USDE_USD_oracle"] = 0x8211B9ae40b06d3Db0215E520F232184Af355378.toBytes32();
        s_values["ethereum"]["Chainlink_USDC_USD_oracle"] = 0x6213f24332D35519039f2afa7e3BffE105a37d3F.toBytes32();
        s_values["ethereum"]["Chainlink_sUSDE_USD_oracle"] = 0xD4fF9D4e0A3E5995A0E040632F34271b2e9c8a42.toBytes32();
        s_values["ethereum"]["Chainlink_USDC_WETH_oracle"] = 0x2eA2b307cD934a6e705eAcFCb6B806d018Cd62CF.toBytes32();
        s_values["ethereum"]["LidoFundamentalOracle"] = 0x7c37aB8Cd76Ee8888ad7F19C1F8a3A6D1622e9B8.toBytes32();

        /* ============= CHAINLINK DATA FEEDS =======================*/
        s_values["ethereum"]["ChainlinkFeed_sUSDE_USD"] = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099.toBytes32();
        s_values["ethereum"]["ChainlinkFeed_USR_USD"] = 0x34ad75691e25A8E9b681AAA85dbeB7ef6561B42c.toBytes32();
        s_values["ethereum"]["ChainlinkFeed_USDC_USD"] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6.toBytes32();
        s_values["ethereum"]["ChainlinkFeed_USDC_ETH"] = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4.toBytes32();
        s_values["ethereum"]["ChainlinkFeed_weETH_ETH"] = 0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22.toBytes32();
    }

    function _addLocalhost() private {}

    function _addEthHoodie() private {
        /* ============ LEVVA VAULTS ========== */
        s_values["ethHoodie"]["LevvaVaultFactory"] = 0x4A3678bD3B2d49EED3937b971D87b5716aCAC789.toBytes32();
        s_values["ethHoodie"]["EulerOracle"] = 0xAD70a0ab951780fF3397882fc5372db83dEb0606.toBytes32();
        s_values["ethHoodie"]["FeeCollector"] = 0xAD70a0ab951780fF3397882fc5372db83dEb0606.toBytes32();
        s_values["ethHoodie"]["VaultManager"] = 0xAD70a0ab951780fF3397882fc5372db83dEb0606.toBytes32();
        s_values["ethHoodie"]["WithdrawQueueFinalizer"] = 0xAD70a0ab951780fF3397882fc5372db83dEb0606.toBytes32();

        /* =========== TOKENS ==================== */
        s_values["ethHoodie"]["USDC"] = 0x0B81B675509e13D192AFd96080217B8b36520A62.toBytes32();
    }

    function _addArbitrum() private {
        s_values["arbitrum"]["LevvaVaultFactory"] = 0x8506934ed8c1154Da93610012524b07A972BAcca.toBytes32();
        s_values["arbitrum"]["EulerOracle"] = 0x9931D4850a10Cc9BcCF44A16CFdaF657CCBbc5a1.toBytes32();
        s_values["arbitrum"]["FeeCollector"] = 0xAD70a0ab951780fF3397882fc5372db83dEb0606.toBytes32();
        s_values["arbitrum"]["VaultManager"] = 0xAD70a0ab951780fF3397882fc5372db83dEb0606.toBytes32();
        s_values["arbitrum"]["WithdrawalQueueFinalizer"] = 0xAD70a0ab951780fF3397882fc5372db83dEb0606.toBytes32();

        /* =========== TOKENS ==================== */
        s_values["arbitrum"]["USDC"] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831.toBytes32();
        s_values["arbitrum"]["WBTC"] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f.toBytes32();
        s_values["arbitrum"]["WETH"] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1.toBytes32();
        s_values["arbitrum"]["aUSDC"] = 0x724dc807b04555b71ed48a6896b6F41593b8C637.toBytes32();

        /* ============== AAVE ================ */
        s_values["arbitrum"]["AavePoolAddressProvider"] = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb.toBytes32();

        /* ============== CURVE ================ */
        s_values["arbitrum"]["CurveRouterV1_2"] = 0x2191718CD32d02B8E60BAdFFeA33E4B5DD9A0A0D.toBytes32();

        /* ============== MORPHO ================ */
        s_values["arbitrum"]["MetaMorphoFactoryV1_1"] = 0x878988f5f561081deEa117717052164ea1Ef0c82.toBytes32();

        /* ============== PENDLE =============== */
        s_values["arbitrum"]["PendleRouter"] = 0x888888888889758F76e7103c6CbF23ABbF58F946.toBytes32();

        /* ============== UNISWAP =============== */
        s_values["arbitrum"]["UniswapV3Router"] = 0xE592427A0AEce92De3Edee1F18E0157C05861564.toBytes32();
        s_values["arbitrum"]["UniversalRouter"] = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3.toBytes32();
        s_values["arbitrum"]["UniswapPermit2"] = 0x000000000022D473030F116dDEE9F6B43aC78BA3.toBytes32();

        /* ============= PRICE ORACLES ============ */
        s_values["arbitrum"]["EulerOracleGovernor"] = 0xAD70a0ab951780fF3397882fc5372db83dEb0606.toBytes32();

        /* ============= CHAINLINK DATA FEEDS =======================*/
        s_values["arbitrum"]["ChainlinkFeed_WETH_USD"] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612.toBytes32();
        s_values["arbitrum"]["ChainlinkFeed_WBTC_USD"] = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57.toBytes32();
        s_values["arbitrum"]["ChainlinkFeed_USDC_USD"] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3.toBytes32();
    }
}
