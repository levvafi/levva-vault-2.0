// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {IAdapter} from "../interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../interfaces/IExternalPositionAdapter.sol";

abstract contract ProtocolActionExecutor is AccessControlUpgradeable {
    /// @custom:storage-location erc7201:levva.storage.MultiAssetVaultBase
    struct ProtocolActionExecutorStorage {
        mapping(bytes4 protocolId => IAdapter) adapters;
        IExternalPositionAdapter[] externalPositionAdapters;
        mapping(address adapter => uint256) externalPositionAdapterPosition;
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
    error WrongAddress();
    error WrongMethod();
    error UnknownExternalPositionAdapter();

    event ProtocolActionExecuted(bytes4 indexed protocolId, bytes data, bytes result);
    event NewAdapterAdded(bytes4 indexed adapterId, address indexed adapter);
    event NewExternalPositionAdapterAdded(address indexed adapter, uint256 indexed position);
    event AdapterRemoved(bytes4 indexed adapterId);
    event ExternalPositionAdapterRemoved(
        address indexed adapter, uint256 indexed position, address indexed replacement
    );

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

    function addAdapter(address adapter) external onlyRole(VAULT_MANAGER_ROLE) {
        if (!IERC165(adapter).supportsInterface(type(IAdapter).interfaceId)) revert WrongAddress();
        // Filtering out 'IExternalPositionAdapter' since they require other method to be added
        if (IERC165(adapter).supportsInterface(type(IExternalPositionAdapter).interfaceId)) revert WrongMethod();
        
        _addAdapter(IAdapter(adapter));
    }

    function addExternalPositionAdapter(address adapter) external onlyRole(VAULT_MANAGER_ROLE) {
        if (!IERC165(adapter).supportsInterface(type(IExternalPositionAdapter).interfaceId)) revert WrongAddress();

        _addAdapter(IAdapter(adapter));
        _addExternalPositionAdapter(IExternalPositionAdapter(adapter));
    }

    function removeAdapter(address adapter) external onlyRole(VAULT_MANAGER_ROLE) {
        // Filtering out 'IExternalPositionAdapter' since they require other method to be removed
        if (IERC165(adapter).supportsInterface(type(IExternalPositionAdapter).interfaceId)) revert WrongMethod();
        
        _removeAdapter(IAdapter(adapter));
    }

    function removeExternalPositionAdapter(address adapter) external onlyRole(VAULT_MANAGER_ROLE) {
        if (!IERC165(adapter).supportsInterface(type(IExternalPositionAdapter).interfaceId)) revert WrongAddress();

        _removeAdapter(IAdapter(adapter));
        _removeExternalPositionAdapter(adapter);
    }


    function _addAdapter(IAdapter adapter) private {
        ProtocolActionExecutorStorage storage $ = _getProtocolActionExecutorStorage();
        bytes4 adapterId = adapter.getAdapterId();
        $.adapters[adapterId] = adapter;

        emit NewAdapterAdded(adapterId, address(adapter));
    }

    function _removeAdapter(IAdapter adapter) private {
        ProtocolActionExecutorStorage storage $ = _getProtocolActionExecutorStorage();
        bytes4 adapterId = adapter.getAdapterId();
        if (address($.adapters[adapterId]) != address(0)) revert UnknownProtocol(adapterId);
        delete $.adapters[adapterId];

        emit AdapterRemoved(adapterId);
    }

    function _addExternalPositionAdapter(IExternalPositionAdapter adapter) private {
        ProtocolActionExecutorStorage storage $ = _getProtocolActionExecutorStorage();

        $.externalPositionAdapters.push(adapter);
        uint256 position = $.externalPositionAdapters.length;
        $.externalPositionAdapterPosition[address(adapter)] = position;

        emit NewExternalPositionAdapterAdded(address(adapter), position);
    }

    function _removeExternalPositionAdapter(address adapter) private {
        ProtocolActionExecutorStorage storage $ = _getProtocolActionExecutorStorage();
        uint256 position = $.externalPositionAdapterPosition[adapter];
        if (position == 0) revert UnknownExternalPositionAdapter();

        address replacement;
        uint256 externalPositionAdaptersCount = $.externalPositionAdapters.length;
        if (position != externalPositionAdaptersCount) {
            replacement = address($.externalPositionAdapters[externalPositionAdaptersCount - 1]);
            $.externalPositionAdapters[position - 1] = IExternalPositionAdapter(replacement);
            $.externalPositionAdapterPosition[replacement] = position;
        }

        $.externalPositionAdapters.pop();
        delete $.externalPositionAdapterPosition[adapter];

        emit ExternalPositionAdapterRemoved(adapter, position, replacement);
    }

    function _getAdapterSafe(bytes4 protocolId) private view returns (address adapter) {
        adapter = address(_getProtocolActionExecutorStorage().adapters[protocolId]);
        if (adapter == address(0)) revert UnknownProtocol(protocolId);
    }
}
