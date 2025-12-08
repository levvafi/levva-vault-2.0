// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC4626AdapterBase} from "../ERC4626AdapterBase.sol";

contract AutoETHAdapter is ERC4626AdapterBase {
    bytes4 public constant getAdapterId = bytes4(keccak256("AutoETHAdapter"));

    constructor(address _wstUSR) ERC4626AdapterBase(_wstUSR) {}

    function WETH() external view returns (address) {
        return _asset;
    }

    function autoETH() external view returns (address) {
        return _vault;
    }
}
