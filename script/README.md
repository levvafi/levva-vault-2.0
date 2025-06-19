# Deploy

## Dry-run mode

Remove `--broadcast` and `--etherscan-api-key` options from script for run a deploy scripts in dry-run mode

If you want to run multiple scripts in dry-run mode run anvil fork an use `http://localhost:8545` as rpc-url in scripts. Set --gas-price option for reasonable value

```sh
anvil --rpc-url $ETH_RPC_URL --gas-price 1000000000
```

If you deploy in dry-run mode ensure `script/deployment/<chainid>/dry-run` directory exists

## Prerequisites

1. Fill `.env` file with correct values
2. Create dry-run directory `script/deployment/<chainid>/dry-run`
3. Run `source .env`

## Deployment steps

1. Deploy LevvaVault factory

```sh
forge script script/DeployLevvaVaultFactory.s.sol:DeployLevvaVaultFactory -vvvv --account deployer --rpc-url $ETH_RPC_URL --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --delay 7 --retries 15
```

2. Before deploying a vault ensure addresses for LevvaVaultFactory, EulerOracle, FeeCollector and VaultManager are set in ChainValues

3. Ensure EulerOracle prices are set up for all tokens. For deploy and set up prices use `https://github.com/levvafi/euler-price-oracle` repo

4. Prepare DeployVault script for concrete vault with implemented getDeployConfig function and run deploy

```sh
forge script script/vault/DeployUSDCVaultExample.s.sol:DeployUSDCVaultExample -vvvv  --account deployer --rpc-url $ETH_RPC_URL --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --delay 7 --retries 15
```

3. Additionally you can deploy adapters and connect it to a vault

```sh
forge script script/DeployAdapter.s.sol:DeployAdapter -vvvv --account deployer --rpc-url $ETH_RPC_URL --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --delay 7 --retries 15
```
