// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapter} from "../interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../interfaces/IExternalPositionAdapter.sol";
import {IAdapterCallback} from "../interfaces/IAdapterCallback.sol";
import {IEulerPriceOracle} from "../interfaces/IEulerPriceOracle.sol";
import {OraclePriceProvider} from "./OraclePriceProvider.sol";

abstract contract AdapterActionExecutor is OraclePriceProvider {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:levva.storage.AdapterActionExecutor
    struct AdapterActionExecutorStorage {
        mapping(bytes4 adapterId => IAdapter) adapters;
        IExternalPositionAdapter[] externalPositionAdapters;
        mapping(address adapter => uint256) externalPositionAdapterPosition;
    }

    // keccak256(abi.encode(uint256(keccak256("levva.storage.AdapterActionExecutor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AdapterActionExecutorStorageLocation =
        0xf9cccbf5436106f61f1caece5dd25c1f0610e9c4a481a50defdeba03abcac100;

    function _getAdapterActionExecutorStorage() private pure returns (AdapterActionExecutorStorage storage $) {
        assembly {
            $.slot := AdapterActionExecutorStorageLocation
        }
    }

    struct AdapterActionArg {
        bytes4 adapterId;
        bytes data;
    }

    event AdapterActionExecuted(bytes4 indexed adapterId, bytes data, bytes result);
    event NewAdapterAdded(bytes4 indexed adapterId, address indexed adapter);
    event NewExternalPositionAdapterAdded(address indexed adapter, uint256 indexed position);
    event AdapterRemoved(bytes4 indexed adapterId);
    event ExternalPositionAdapterRemoved(
        address indexed adapter, uint256 indexed position, address indexed replacement
    );

    error UnknownAdapter(bytes4 adapterId);
    error WrongAddress();
    error UnknownExternalPositionAdapter();
    error AdapterAlreadyExists(address adapter);
    error Forbidden();

    function executeAdapterAction(AdapterActionArg[] calldata actionArgs) external onlyVaultManager {
        uint256 length = actionArgs.length;
        uint256 i;
        for (; i < length;) {
            AdapterActionArg memory actionArg = actionArgs[i];

            address adapter = _getAdapterSafe(actionArg.adapterId);
            bytes memory result = Address.functionDelegateCall(adapter, actionArg.data);

            emit AdapterActionExecuted(actionArg.adapterId, actionArg.data, result);

            unchecked {
                ++i;
            }
        }
    }

    function addAdapter(address adapter, bytes memory initializeCallData) external onlyOwner {
        if (!_isAdapter(adapter)) revert WrongAddress();
        _addAdapter(IAdapter(adapter));

        if (_isExternalPositionAdapter(adapter)) {
            _addExternalPositionAdapter(IExternalPositionAdapter(adapter));
        }

        if (initializeCallData.length > 0) {
            Address.functionDelegateCall(adapter, initializeCallData);
        }
    }

    function removeAdapter(address adapter) external onlyOwner {
        _removeAdapter(IAdapter(adapter));

        if (_isExternalPositionAdapter(adapter)) {
            _removeExternalPositionAdapter(adapter);
        }
    }

    function getAdapter(bytes4 adapterId) external view returns (IAdapter) {
        return _getAdapterActionExecutorStorage().adapters[adapterId];
    }

    function externalPositionAdapterPosition(address adapter) external view returns (uint256) {
        return _getAdapterActionExecutorStorage().externalPositionAdapterPosition[adapter];
    }

    function _addAdapter(IAdapter adapter) private {
        AdapterActionExecutorStorage storage $ = _getAdapterActionExecutorStorage();
        bytes4 adapterId = adapter.getAdapterId();
        if (address($.adapters[adapterId]) != address(0)) revert AdapterAlreadyExists(address($.adapters[adapterId]));
        $.adapters[adapterId] = adapter;

        emit NewAdapterAdded(adapterId, address(adapter));
    }

    function _removeAdapter(IAdapter adapter) private {
        AdapterActionExecutorStorage storage $ = _getAdapterActionExecutorStorage();
        bytes4 adapterId = adapter.getAdapterId();
        if (address($.adapters[adapterId]) == address(0)) revert UnknownAdapter(adapterId);
        delete $.adapters[adapterId];

        emit AdapterRemoved(adapterId);
    }

    function _addExternalPositionAdapter(IExternalPositionAdapter adapter) private {
        AdapterActionExecutorStorage storage $ = _getAdapterActionExecutorStorage();

        $.externalPositionAdapters.push(adapter);
        uint256 position = $.externalPositionAdapters.length;
        $.externalPositionAdapterPosition[address(adapter)] = position;

        emit NewExternalPositionAdapterAdded(address(adapter), position);
    }

    function _removeExternalPositionAdapter(address adapter) private {
        AdapterActionExecutorStorage storage $ = _getAdapterActionExecutorStorage();
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
        adapter = address(_getAdapterActionExecutorStorage().adapters[adapterId]);
        if (adapter == address(0)) revert UnknownAdapter(adapterId);
    }

    function _isAdapter(address adapter) private view returns (bool) {
        return IERC165(adapter).supportsInterface(type(IAdapter).interfaceId);
    }

    function _isExternalPositionAdapter(address adapter) private view returns (bool) {
        return IERC165(adapter).supportsInterface(type(IExternalPositionAdapter).interfaceId);
    }

    function _getExternalPositionAdaptersTotalAssets(IEulerPriceOracle eulerOracle, address asset)
        internal
        view
        returns (uint256 totalAssets)
    {
        unchecked {
            AdapterActionExecutorStorage storage $ = _getAdapterActionExecutorStorage();
            uint256 length = $.externalPositionAdapters.length;
            for (uint256 i; i < length; ++i) {
                IExternalPositionAdapter adapter = $.externalPositionAdapters[i];

                (address[] memory managedAssets, uint256[] memory managedAmounts) = adapter.getManagedAssets();
                uint256 assetsLength = managedAssets.length;
                for (uint256 j; j < assetsLength; ++j) {
                    totalAssets += _callOracle(eulerOracle, managedAmounts[i], managedAssets[i], asset);
                }

                (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
                assetsLength = debtAssets.length;
                for (uint256 j; j < assetsLength; ++j) {
                    totalAssets -= _callOracle(eulerOracle, debtAmounts[i], debtAssets[i], asset);
                }
            }
        }
    }
}
