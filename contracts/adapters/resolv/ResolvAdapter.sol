// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {ERC4626AdapterBase} from "../ERC4626AdapterBase.sol";

contract ResolvAdapter is ERC4626AdapterBase {
    using SafeERC20 for IERC4626;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("ResolvAdapter"));

    constructor(address _wstUSR) ERC4626AdapterBase(_wstUSR) {}

    function USR() public view returns (address) {
        return _asset;
    }

    function wstUSR() public view returns (IERC4626) {
        return IERC4626(_vault);
    }
}
