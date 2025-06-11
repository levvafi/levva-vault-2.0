// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DeployHelper} from "./DeployHelper.s.sol";

///@dev forge script script/DeployLevvaVaultFactory.s.sol:DeployLevvaVaultFactory -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract DeployLevvaVaultFactory is Script, DeployHelper {
    using stdJson for string;
    using Strings for address;

    string public constant DEPLOYMENT_FILE = "factory.json";

    struct FactoryDeployment {
        address factoryProxy;
        address factoryImplementation;
        address levvaVaultImplementation;
        address withdrawalQueueImplementation;
    }

    function run() external {
        address deployedFactory = getDeployedFactoryAddress();
        if (deployedFactory != address(0)) {
            console.log("Factory already deployed at", deployedFactory.toHexString());
            return;
        }

        deployFactory();
    }

    function getOrDeployFactory() public returns (address) {
        address deployedFactory = getDeployedFactoryAddress();
        if (deployedFactory == address(0)) {
            deployedFactory = deployFactory();
        }
        return deployedFactory;
    }

    function getDeployedFactoryAddress() public returns (address) {
        return _getDeployment().factoryProxy;
    }

    function deployFactory() public returns (address) {
        vm.startBroadcast();
        address levvaVaultImplementation = address(new LevvaVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address levvaVaultFactoryImplementation = address(new LevvaVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            LevvaVaultFactory.initialize.selector, levvaVaultImplementation, withdrawalQueueImplementation
        );

        ERC1967Proxy levvaVaultFactoryProxy = new ERC1967Proxy(levvaVaultFactoryImplementation, data);
        vm.stopBroadcast();

        FactoryDeployment memory deployment;
        deployment.factoryProxy = address(levvaVaultFactoryProxy);
        deployment.factoryImplementation = levvaVaultFactoryImplementation;
        deployment.levvaVaultImplementation = levvaVaultImplementation;
        deployment.withdrawalQueueImplementation = withdrawalQueueImplementation;

        _saveDeployment(deployment);

        return deployment.factoryProxy;
    }

    function _getDeployment() private returns (FactoryDeployment memory deployment) {
        string memory filePath = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(filePath)) {
            _saveDeployment(deployment);
            return deployment;
        }

        string memory jsonFile = vm.readFile(filePath);
        deployment = abi.decode(vm.parseJson(jsonFile), (FactoryDeployment));
    }

    function _saveDeployment(FactoryDeployment memory deployment) private {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);

        string memory obj = "";
        vm.serializeAddress(obj, "factoryProxy", deployment.factoryProxy);
        vm.serializeAddress(obj, "factoryImplementation", deployment.factoryImplementation);
        vm.serializeAddress(obj, "levvaVaultImplementation", deployment.levvaVaultImplementation);
        string memory output =
            vm.serializeAddress(obj, "withdrawalQueueImplementation", deployment.withdrawalQueueImplementation);
        vm.writeJson(output, path);
    }
}
