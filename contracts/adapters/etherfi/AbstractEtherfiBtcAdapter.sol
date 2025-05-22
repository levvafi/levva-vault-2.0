// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {ILayerZeroTellerWithRateLimiting} from "./interfaces/ILayerZeroTellerWithRateLimiting.sol";

abstract contract AbstractEtherfiBtcAdapter is AdapterBase, ERC721Holder, IExternalPositionAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;

    IERC20 public immutable wBTC;
    IERC20 public immutable eBTC;
    ILayerZeroTellerWithRateLimiting public immutable teller;

    constructor(address _wBTC, address _eBTC, address _teller) {
        _wBTC.assertNotZeroAddress();
        _eBTC.assertNotZeroAddress();
        _teller.assertNotZeroAddress();

        wBTC = IERC20(_wBTC);
        eBTC = IERC20(_eBTC);
        teller = ILayerZeroTellerWithRateLimiting(_teller);
    }

    function depositBtc(uint256 amount) external returns (uint256 shares) {
        IERC20 _wBTC = wBTC;
        IERC20 _eBTC = eBTC;

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_wBTC), amount);
        _wBTC.forceApprove(address(_eBTC), amount);

        shares = teller.deposit(_wBTC, amount, 0);
        _eBTC.safeTransfer(msg.sender, amount);
    }
}
