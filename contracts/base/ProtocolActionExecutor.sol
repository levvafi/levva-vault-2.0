// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {IAdapter} from "../interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../interfaces/IExternalPositionAdapter.sol";

abstract contract ProtocolActionExecutor is AccessControlUpgradeable, Ownable2StepUpgradeable {
    /// @custom:storage-location erc7201:levva.storage.MultiAssetVaultBase
    struct ProtocolActionExecutorStorage {
        mapping(bytes4 adapterId => IAdapter) adapters;
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
        bytes4 adapterId;
        bytes data;
    }

    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    event ProtocolActionExecuted(bytes4 indexed adapterId, bytes data, bytes result);
    event NewAdapterAdded(bytes4 indexed adapterId, address indexed adapter);
    event NewExternalPositionAdapterAdded(address indexed adapter, uint256 indexed position);
    event AdapterRemoved(bytes4 indexed adapterId);
    event ExternalPositionAdapterRemoved(
        address indexed adapter, uint256 indexed position, address indexed replacement
    );

    error UnknownProtocol(bytes4 adapterId);
    error WrongAddress();
    error UnknownExternalPositionAdapter();
    error AdapterAlreadyExists(address adapter);

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

            address adapter = _getAdapterSafe(actionArg.adapterId);
            bytes memory result = Address.functionCall(adapter, actionArg.data);
            returnData[i] = result;

            emit ProtocolActionExecuted(actionArg.adapterId, actionArg.data, result);

            unchecked {
                ++i;
            }
        }
    }

    function addAdapter(address adapter) external onlyOwner {
        if (!_isAdapter(adapter)) revert WrongAddress();
        _addAdapter(IAdapter(adapter));

        if (_isExternalPositionAdapter(adapter)) {
            _addExternalPositionAdapter(IExternalPositionAdapter(adapter));
        }
    }

    function removeAdapter(address adapter) external onlyOwner {
        _removeAdapter(IAdapter(adapter));

        if (_isExternalPositionAdapter(adapter)) {
            _removeExternalPositionAdapter(adapter);
        }
    }

    function getAdapter(bytes4 adapterId) external view returns (IAdapter) {
        return _getProtocolActionExecutorStorage().adapters[adapterId];
    }

    function externalPositionAdapterPosition(address adapter) external view returns (uint256) {
        return _getProtocolActionExecutorStorage().externalPositionAdapterPosition[adapter];
    }

    function _addAdapter(IAdapter adapter) private {
        ProtocolActionExecutorStorage storage $ = _getProtocolActionExecutorStorage();
        bytes4 adapterId = adapter.getAdapterId();
        if (address($.adapters[adapterId]) != address(0)) revert AdapterAlreadyExists(address($.adapters[adapterId]));
        $.adapters[adapterId] = adapter;

        emit NewAdapterAdded(adapterId, address(adapter));
    }

    function _removeAdapter(IAdapter adapter) private {
        ProtocolActionExecutorStorage storage $ = _getProtocolActionExecutorStorage();
        bytes4 adapterId = adapter.getAdapterId();
        if (address($.adapters[adapterId]) == address(0)) revert UnknownProtocol(adapterId);
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

    function _getAdapterSafe(bytes4 adapterId) private view returns (address adapter) {
        adapter = address(_getProtocolActionExecutorStorage().adapters[adapterId]);
        if (adapter == address(0)) revert UnknownProtocol(adapterId);
    }

    function _isAdapter(address adapter) private view returns (bool) {
        return IERC165(adapter).supportsInterface(type(IAdapter).interfaceId);
    }

    function _isExternalPositionAdapter(address adapter) private view returns (bool) {
        return IERC165(adapter).supportsInterface(type(IExternalPositionAdapter).interfaceId);
    }
}
