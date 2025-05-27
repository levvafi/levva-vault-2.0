// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapterCallback} from "../interfaces/IAdapterCallback.sol";
import {Asserts} from "../libraries/Asserts.sol";
import {AdapterBase} from "./AdapterBase.sol";

abstract contract ERC4626AdapterBase is AdapterBase {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC4626;
    using Asserts for address;

    address internal immutable _vault;
    address internal immutable _asset;

    constructor(address vault) {
        vault.assertNotZeroAddress();

        _vault = vault;
        _asset = IERC4626(_vault).asset();
    }

    function deposit(uint256 assets) external virtual returns (uint256 shares) {
        IERC4626 vault = IERC4626(_vault);
        _ensureIsValidAsset(address(_vault));

        address asset = _asset;
        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, assets);
        IERC20(asset).forceApprove(address(vault), assets);

        shares = vault.deposit(assets, msg.sender);
    }

    function redeem(uint256 shares) external virtual returns (uint256 withdrawn) {
        _ensureIsValidAsset(_asset);
        IERC4626 vault = IERC4626(_vault);

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(vault), shares);
        vault.forceApprove(address(_vault), shares);

        withdrawn = vault.redeem(shares, msg.sender, address(this));
    }
}
