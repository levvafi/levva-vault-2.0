// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AbstractEtherfiEthAdapter} from "./AbstractEtherfiEthAdapter.sol";

contract EtherfiAdapter is AbstractEtherfiEthAdapter {
    bytes4 public constant getAdapterId = bytes4(keccak256("EtherfiAdapter"));

    constructor(address weth, address liquidityPool) AbstractEtherfiEthAdapter(weth, liquidityPool) {}
}
