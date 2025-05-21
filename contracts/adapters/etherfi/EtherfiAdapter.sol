// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {AbstractEtherfiEthAdapter} from "./AbstractEtherfiEthAdapter.sol";

contract EtherfiAdapter is AbstractEtherfiEthAdapter {
    bytes4 public constant getAdapterId = bytes4(keccak256("EtherfiAdapter"));

    constructor(address weth, address liquidityPool) AbstractEtherfiEthAdapter(weth, liquidityPool) {}

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IExternalPositionAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IExternalPositionAdapter
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        return _getManagedAssets(msg.sender);
    }

    function getManagedAssets(address vault)
        external
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        return _getManagedAssets(vault);
    }

    /// @inheritdoc IExternalPositionAdapter
    /// @dev there is no debt assets
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function _getManagedAssets(address vault)
        private
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        assets = new address[](1);
        assets[0] = address(weth);

        amounts = new uint256[](1);
        amounts[0] = _getPendingEthAmount(vault);
    }
}
