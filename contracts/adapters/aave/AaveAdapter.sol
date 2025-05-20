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

contract AaveAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("AaveAdapter"));

    IPoolAddressesProvider public immutable aavePoolAddressProvider;
    constructor(address _aavePoolAddressProvider) {
        _aavePoolAddressProvider.assertNotZeroAddress();
        aavePoolAddressProvider = IPoolAddressesProvider(_aavePoolAddressProvider);
    }

    function supply(address asset, uint256 amount) external {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, amount);
        IERC20(asset).forceApprove(address(aavePool), amount);
        aavePool.supply(asset, amount, msg.sender, 0);
    }

    function withdraw(address asset, uint256 amount) external {
        IPool aavePool = IPool(aavePoolAddressProvider.getPool());

        address aToken = _getAToken(aavePool, asset);
        uint256 toTransfer = amount == type(uint256).max ? IERC20(aToken).balanceOf(msg.sender) : amount;
        IAdapterCallback(msg.sender).adapterCallback(address(this), aToken, toTransfer);
        IERC20(asset).forceApprove(aToken, toTransfer);

        aavePool.withdraw(asset, amount, msg.sender);
    }

    function _getAToken(IPool pool, address asset) private view returns (address) {
        return pool.getReserveData(asset).aTokenAddress;
    }
}
