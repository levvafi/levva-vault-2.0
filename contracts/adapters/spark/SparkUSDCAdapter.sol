// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC4626AdapterBase} from "../ERC4626AdapterBase.sol";

contract SparkUSDCAdapter is ERC4626AdapterBase {
    bytes4 public constant getAdapterId = bytes4(keccak256("SparkUSDCAdapter"));

    constructor(address _sparkUSDC) ERC4626AdapterBase(_sparkUSDC) {}

    function USDC() external view returns (address) {
        return _asset;
    }

    function sparkUSDC() external view returns (address) {
        return _vault;
    }
}
