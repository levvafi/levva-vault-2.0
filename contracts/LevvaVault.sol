// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/Extensions/ERC4626Upgradeable.sol";

contract LevvaVault is ERC4626Upgradeable {
    constructor() payable {}
}
