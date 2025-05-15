// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {AbstractUniswapV3Adapter} from "./AbstractUniswapV3Adapter.sol";
import {AbstractUniswapV4Adapter} from "./AbstractUniswapV4Adapter.sol";

contract UniswapAdapter is IERC165, AbstractUniswapV3Adapter, AbstractUniswapV4Adapter {
    bytes4 public constant getAdapterId = bytes4(keccak256("UniswapAdapter"));

    constructor(address v3Router, address universalRouter)
        AbstractUniswapV3Adapter(v3Router)
        AbstractUniswapV4Adapter(universalRouter)
    {}
}
