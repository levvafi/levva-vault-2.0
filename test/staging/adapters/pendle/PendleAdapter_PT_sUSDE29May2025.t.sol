// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PendleAdapter} from "../../../../contracts/adapters/pendle/PendleAdapter.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    SwapType,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";
import {PendleAdapterTestBase} from "./PendleAdapterTestBase.t.sol";

contract PendleAdapterTest is PendleAdapterTestBase {
    address internal constant OLD_PENDLE_MARKET = 0xB162B764044697cf03617C2EFbcB1f42e31E4766; //PT-sUSDE29May2025
    address internal constant NEW_PENDLE_MARKET = 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac; //PT-sUSDE31Jul2025

    function setUp() public override {
        super.setUp();
        vm.rollFork(22_480_700);
    }

    function test_rollOverPt() public {
        uint256 ptAmount = 150e18; // 150 PT-sUSDE29May2025
        uint256 minNewPtOut = 100e18; // 100 PT-sUSDE31Jul2025

        _rollOverPt(OLD_PENDLE_MARKET, NEW_PENDLE_MARKET, ptAmount, minNewPtOut);
    }

    function test_rollOverPt_AfterMaturity() public {
        vm.warp(1748563200); // 30 may 2025

        uint256 ptAmount = 150e18; // 150 PT-sUSDE29May2025
        uint256 minNewPtOut = 100e18; // 100 PT-sUSDE31Jul2025

        _rollOverPt(OLD_PENDLE_MARKET, NEW_PENDLE_MARKET, ptAmount, minNewPtOut);
    }
}
