// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployHelper} from "./helper/DeployHelper.sol";

interface IEulerRouterFactory {
    function deploy(address governor) external returns (address);
}

///@dev forge script script/DeployEulerPriceOracle.s.sol:DeployEulerPriceOracle -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract DeployEulerPriceOracle is Script, DeployHelper {
    string public constant DEPLOYMENT_FILE = "price-oracle.json";

    function run() external {
        /* 
        * We use EulerOracleFactory from euler.finance to deploy euler price oracle 
        */
        address eulerOracleFactory = getAddress("EulerOracleFactory");
        address eulerOracleGovernor = getAddress("EulerOracleGovernor");

        vm.broadcast();
        address eulerOracle = IEulerRouterFactory(eulerOracleFactory).deploy(eulerOracleGovernor);

        _saveDeployment(eulerOracle);
    }

    function _saveDeployment(address eulerOracle) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(path)) {
            _createEmptyDeploymentFile(path);
        }

        _saveInDeploymentFile(path, "EulerOracle", eulerOracle);
    }
}
