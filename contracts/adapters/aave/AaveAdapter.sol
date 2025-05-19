// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {IMultiAssetVault} from "../../interfaces/IMultiAssetVault.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {AdapterBase} from "../AdapterBase.sol";

contract AaveAdapter is AdapterBase, IExternalPositionAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;
    using WadRayMath for uint256;

    bytes4 public constant getAdapterId = bytes4(keccak256("AaveAdapter"));

    IPoolAddressesProvider public immutable aavePoolAddressProvider;
    mapping(address vault => mapping(address aToken => uint256)) vaultATokenPosition;
    mapping(address vault => address[]) vaultATokens;
    mapping(address vault => uint256[]) vaultATokenAmounts;

    constructor(address _aavePoolAddressProvider) {
        _aavePoolAddressProvider.assertNotZeroAddress();
        aavePoolAddressProvider = IPoolAddressesProvider(_aavePoolAddressProvider);
    }

    function supply(address asset, uint256 supplyTokenAmount) external {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());

        IERC20(asset).forceApprove(address(aavePool), supplyTokenAmount);
        aavePool.supply(asset, supplyTokenAmount, msg.sender, 0);

        _increaseATokenAmount(_getAToken(aavePool, asset), supplyTokenAmount);
    }

    function withdraw(address asset, uint256 aTokenAmount) external {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());
        aavePool.withdraw(asset, aTokenAmount, msg.sender);
        _decreaseATokenAmount(_getAToken(aavePool, asset), aTokenAmount);
    }

    /// @inheritdoc IExternalPositionAdapter
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        assets = vaultATokens[msg.sender];
        amounts = vaultATokenAmounts[msg.sender];
    }

    /// @inheritdoc IExternalPositionAdapter
    /// @dev no debt functionality
    function getDebtAssets() external pure returns (address[] memory assets, uint256[] memory amounts) {}

    function _increaseATokenAmount(address aToken, uint256 delta) private {
        uint256 aTokenPosition = vaultATokenPosition[msg.sender][aToken];
        if (aTokenPosition == 0) {
            vaultATokens[msg.sender].push(aToken);
            vaultATokenAmounts[msg.sender].push(delta);
            vaultATokenPosition[msg.sender][aToken] = vaultATokens[msg.sender].length;
            return;
        }

        vaultATokenAmounts[msg.sender][aTokenPosition - 1] += delta;
    }

    function _decreaseATokenAmount(address aToken, uint256 delta) private {
        uint256 aTokenPosition = vaultATokenPosition[msg.sender][aToken];
        if (aTokenPosition == 0) revert();

        uint256 aTokenIndex = aTokenPosition - 1;
        uint256 currentAmount = vaultATokenAmounts[msg.sender][aTokenIndex];

        if (currentAmount != delta) {
            uint256 aTokensLastIndex = vaultATokens[msg.sender].length - 1;
            if (aTokenIndex != aTokensLastIndex) {
                vaultATokens[msg.sender][aTokenIndex] = vaultATokens[msg.sender][aTokensLastIndex];
                vaultATokenAmounts[msg.sender][aTokenIndex] = vaultATokenAmounts[msg.sender][aTokensLastIndex];
            }

            delete vaultATokens[msg.sender][aTokensLastIndex];
            delete vaultATokenAmounts[msg.sender][aTokensLastIndex];
        } else {
            vaultATokenAmounts[msg.sender][aTokenIndex] = currentAmount - delta;
        }
    }

    function _getAToken(IPool pool, address asset) private view returns (address) {
        return pool.getReserveData(asset).aTokenAddress;
    }
}
