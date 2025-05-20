// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IScaledBalanceToken} from "@aave/core-v3/contracts/interfaces/IScaledBalanceToken.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {IMultiAssetVault} from "../../interfaces/IMultiAssetVault.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {AdapterBase} from "../AdapterBase.sol";

contract AaveAdapter is AdapterBase, IExternalPositionAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("AaveAdapter"));

    IPoolAddressesProvider public immutable aavePoolAddressProvider;
    mapping(address vault => mapping(address aToken => uint256)) vaultATokenPosition;
    mapping(address vault => address[]) vaultATokens;

    constructor(address _aavePoolAddressProvider) {
        _aavePoolAddressProvider.assertNotZeroAddress();
        aavePoolAddressProvider = IPoolAddressesProvider(_aavePoolAddressProvider);
    }

    function supply(address asset, uint256 amount) external {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, amount);
        IERC20(asset).forceApprove(address(aavePool), amount);
        aavePool.supply(asset, amount, msg.sender, 0);

        _addAToken(_getAToken(aavePool, asset));
    }

    function withdraw(address asset, uint256 amount) external {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());

        address aToken = _getAToken(aavePool, asset);
        uint256 toTransfer = amount == type(uint256).max ? IERC20(aToken).balanceOf(msg.sender) : amount;
        IAdapterCallback(msg.sender).adapterCallback(address(this), aToken, toTransfer);
        IERC20(asset).forceApprove(aToken, toTransfer);

        aavePool.withdraw(asset, amount, msg.sender);

        _removeAToken(_getAToken(aavePool, asset));
    }

    /// @inheritdoc IExternalPositionAdapter
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        return _getVaultManagedAssets(msg.sender);
    }

    function getVaultManagedAssets(address vault)
        external
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        return _getVaultManagedAssets(vault);
    }

    /// @inheritdoc IExternalPositionAdapter
    /// @dev no debt functionality
    function getDebtAssets() external pure returns (address[] memory assets, uint256[] memory amounts) {}

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return type(IExternalPositionAdapter).interfaceId == interfaceId || super.supportsInterface(interfaceId);
    }

    function _addAToken(address aToken) private {
        uint256 aTokenPosition = vaultATokenPosition[msg.sender][aToken];
        if (aTokenPosition != 0) return;

        vaultATokens[msg.sender].push(aToken);
        vaultATokenPosition[msg.sender][aToken] = vaultATokens[msg.sender].length;
    }

    function _removeAToken(address aToken) private {
        if (IScaledBalanceToken(aToken).scaledBalanceOf(msg.sender) != 0) return;

        uint256 aTokenIndex = vaultATokenPosition[msg.sender][aToken] - 1;
        uint256 aTokensLastIndex = vaultATokens[msg.sender].length - 1;
        if (aTokenIndex != aTokensLastIndex) {
            vaultATokens[msg.sender][aTokenIndex] = vaultATokens[msg.sender][aTokensLastIndex];
        }

        vaultATokens[msg.sender].pop();
    }

    function _getAToken(IPool pool, address asset) private view returns (address) {
        return pool.getReserveData(asset).aTokenAddress;
    }

    function _getVaultManagedAssets(address vault)
        private
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        assets = vaultATokens[vault];
        uint256 assetsLength = assets.length;
        amounts = new uint256[](assetsLength);

        unchecked {
            for (uint256 i; i < assetsLength; ++i) {
                amounts[i] = IERC20(assets[i]).balanceOf(vault);
            }
        }
    }
}
