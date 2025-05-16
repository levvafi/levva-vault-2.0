// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AdapterVaultMock} from "./AdapterVaultMock.t.sol";
import {CurveRouterAdapter} from "../../contracts/adapters/curve/CurveRouterAdapter.sol";

contract CurveAdapterVaultMock is AdapterVaultMock {
    CurveRouterAdapter public immutable s_curveAdapter;

    constructor(address curveAdapter, address _asset) AdapterVaultMock(_asset) {
        s_curveAdapter = CurveRouterAdapter(curveAdapter);
    }

    function exchange(
        address[11] memory route,
        uint256[5][5] memory swapParams,
        uint256 amount,
        uint256 minDy,
        address[5] memory pools
    ) external {
        s_curveAdapter.exchange(route, swapParams, amount, minDy, pools);
    }
}
