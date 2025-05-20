// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {AdapterBase} from "../AdapterBase.sol";

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/interfaces/IERC4626.sol';

import {ILevvaPool} from './ILevvaPool.sol';
import {FP96} from './FP96.sol';

contract LevvaPoolAdapter is AdapterBase {
    bytes4 public constant getAdapterId = bytes4(keccak256("LevvaPoolAdapter"));

    constructor()
    {}
}
