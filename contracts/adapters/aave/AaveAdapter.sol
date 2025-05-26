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

    /// @custom:storage-location erc7201:levva.storage.AaveAdapterStorage
    struct AaveAdapterStorage {
        IPoolAddressesProvider aavePoolAddressProvider;
    }

    // keccak256(abi.encode(uint256(keccak256("levva.storage.AaveAdapterStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AdapterAdapterStorageLocation =
        0x10e3677d8185beaddb1f8b8d5deec589b0a3b430df8f87cd7942442cfd6f2000;

    function _getAaveAdapterStorage() private pure returns (AaveAdapterStorage storage $) {
        assembly {
            $.slot := AdapterAdapterStorageLocation
        }
    }

    function initialize(address aavePoolAddressProvider) external onlyOwner {
        aavePoolAddressProvider.assertNotZeroAddress();
        _getAaveAdapterStorage().aavePoolAddressProvider = IPoolAddressesProvider(aavePoolAddressProvider);
    }

    function getPoolAddressProvider() external view returns (address) {
        return address(_getAaveAdapterStorage().aavePoolAddressProvider);
    }

    function supply(address asset, uint256 amount) external {
        IPool aavePool = IPool(_getAaveAdapterStorage().aavePoolAddressProvider.getPool());

        address aToken = _getAToken(aavePool, asset);
        _ensureIsValidAsset(aToken);

        IERC20(asset).forceApprove(address(aavePool), amount);
        aavePool.supply(asset, amount, address(this), 0);
    }

    function withdraw(address asset, uint256 amount) external {
        _ensureIsValidAsset(asset);

        IPool aavePool = IPool(_getAaveAdapterStorage().aavePoolAddressProvider.getPool());
        address aToken = _getAToken(aavePool, asset);

        uint256 toTransfer = amount == type(uint256).max ? IERC20(aToken).balanceOf(address(this)) : amount;
        IERC20(asset).forceApprove(aToken, toTransfer);

        aavePool.withdraw(asset, amount, address(this));
    }

    function _getAToken(IPool pool, address asset) private view returns (address) {
        return pool.getReserveData(asset).aTokenAddress;
    }
}
