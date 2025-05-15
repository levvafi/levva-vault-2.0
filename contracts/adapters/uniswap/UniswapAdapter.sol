// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {AbstractUniswapV3Adapter} from "./AbstractUniswapV3Adapter.sol";

contract UniswapAdapter is IERC165, AbstractUniswapV3Adapter {
    bytes4 public constant getAdapterId = bytes4(keccak256("UniswapAdapter"));

    constructor(address v3Router) AbstractUniswapV3Adapter(v3Router) {}
}
