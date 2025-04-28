// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {IAdapter} from "../interfaces/IAdapter.sol";

abstract contract ProtocolActionExecutor is AccessControlUpgradeable {
    /// @custom:storage-location erc7201:levva.storage.MultiAssetVaultBase
    struct ProtocolActionExecutorStorage {
        mapping(bytes4 protocolId => IAdapter) adapters;
    }

    // keccak256(abi.encode(uint256(keccak256("levva.storage.ProtocolActionExecutor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ProtocolActionExecutorStorageLocation =
        0xf94d625fef261094d19c6719f6b3215eef5369f54701b322d0499341782a3700;

    function _getProtocolActionExecutorStorage() private pure returns (ProtocolActionExecutorStorage storage $) {
        assembly {
            $.slot := ProtocolActionExecutorStorageLocation
        }
    }

    struct ProtocolActionArg {
        bytes4 protocolId;
        bytes data;
    }

    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    error UnknownProtocol(bytes4 protocolId);

    event ProtocolActionExecuted(bytes4 indexed protocolId, bytes data, bytes result);

    function executeProtocolAction(ProtocolActionArg[] calldata actionArgs)
        external
        onlyRole(VAULT_MANAGER_ROLE)
        returns (bytes[] memory returnData)
    {
        uint256 length = actionArgs.length;
        uint256 i;
        returnData = new bytes[](length);
        for (; i < length;) {
            ProtocolActionArg memory actionArg = actionArgs[i];

            address adapter = _getAdapterSafe(actionArg.protocolId);
            bytes memory result = Address.functionCall(adapter, actionArg.data);
            returnData[i] = result;

            emit ProtocolActionExecuted(actionArg.protocolId, actionArg.data, result);

            unchecked {
                ++i;
            }
        }
    }

    function _getAdapterSafe(bytes4 protocolId) private view returns (address adapter) {
        adapter = address(_getProtocolActionExecutorStorage().adapters[protocolId]);
        if (adapter == address(0)) revert UnknownProtocol(protocolId);
    }
}
