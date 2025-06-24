// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {LevvaVaultFactory} from "contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "contracts/LevvaVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployHelper} from "./helper/DeployHelper.sol";

///@dev Before deploy: create directory "deployment/{chainId}/dry-run" for dry-run or create "deployment/{chainId}" for deploy
///@dev forge script script/DeployLevvaVaultFactory.s.sol:DeployLevvaVaultFactory -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract DeployLevvaVaultFactory is Script, DeployHelper {
    using stdJson for string;

    string public constant DEPLOYMENT_FILE = "factory.json";

    struct FactoryDeployment {
        address factoryImplementation;
        address factoryProxy;
        address levvaVaultImplementation;
        address withdrawalQueueImplementation;
    }

    function run() external {
        _createDeploymentFileIfNotExists();

        address deployedFactory = getDeployedFactoryAddress();
        if (deployedFactory != address(0)) {
            console.log("Factory already deployed at", vm.toString(deployedFactory));
            return;
        }

        deployFactory();
    }

    function getDeployedFactoryAddress() public view returns (address) {
        address factoryAddress = _getDeployment().factoryProxy;
        if (factoryAddress.code.length == 0) {
            return address(0);
        }

        return factoryAddress;
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

    function _createDeploymentFileIfNotExists() private {
        string memory filePath = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(filePath)) {
            FactoryDeployment memory deployment;
            _saveDeployment(deployment);
        }
    }

    function _getDeployment() private view returns (FactoryDeployment memory deployment) {
        string memory filePath = _getDeploymentPath(DEPLOYMENT_FILE);
        string memory jsonFile = vm.readFile(filePath);

        deployment.factoryImplementation = vm.parseJsonAddress(jsonFile, ".FactoryImplementation");
        deployment.factoryProxy = vm.parseJsonAddress(jsonFile, ".FactoryProxy");
        deployment.levvaVaultImplementation = vm.parseJsonAddress(jsonFile, ".LevvaVaultImplementation");
        deployment.withdrawalQueueImplementation = vm.parseJsonAddress(jsonFile, ".WithdrawalQueueImplementation");
    }

    function _saveDeployment(FactoryDeployment memory deployment) private {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);

        string memory obj = "";
        vm.serializeAddress(obj, "FactoryProxy", deployment.factoryProxy);
        vm.serializeAddress(obj, "FactoryImplementation", deployment.factoryImplementation);
        vm.serializeAddress(obj, "LevvaVaultImplementation", deployment.levvaVaultImplementation);
        string memory output =
            vm.serializeAddress(obj, "WithdrawalQueueImplementation", deployment.withdrawalQueueImplementation);
        vm.writeJson(output, path);
    }
}
