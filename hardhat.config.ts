import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import 'hardhat-contract-sizer';
import { config as dotEnvConfig } from 'dotenv';
import '@nomicfoundation/hardhat-foundry';
// import "./tasks/deploy";

dotEnvConfig();

const config: HardhatUserConfig & { contractSizer: any } = {
    solidity: {
        compilers: [
            {
                version: '0.8.28',
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1000000,
                    },
                },
            },
        ],
    },
    etherscan: {
        apiKey: process.env.API_KEY,
    },
    mocha: {
        timeout: 2_000_000,
    },
    contractSizer: {
        alphaSort: true,
        disambiguatePaths: false,
        runOnCompile: true,
        strict: false,
        only: ['Levva', 'Vesting', 'Staking', 'TokenMinter'],
        except: ['Mock', 'Test'],
    },
    sourcify: {
        enabled: false,
    },
    networks: {
        ethereum: {
            url: process.env.ETH_RPC_URL,
        },
        sepolia: {
            url: process.env.SEPOLIA_RPC_URL,
        },
    },
};

export default config;
