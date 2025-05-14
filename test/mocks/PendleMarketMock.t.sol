// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {MintableERC20} from "./MintableERC20.t.sol";
import {IStandardizedYield} from "@pendle/core-v2/contracts/interfaces/IStandardizedYield.sol";
import {IPPrincipalToken} from "@pendle/core-v2/contracts/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "@pendle/core-v2/contracts/interfaces/IPYieldToken.sol";

/// @dev Mintable ERC20 token.
contract PendleMarketMock is MintableERC20 {
    address private immutable ptToken;
    address private immutable syToken;
    bool private s_isExpired;

    constructor(address _ptToken, address _syToken, string memory name, string memory symbol, uint8 decimals_)
        MintableERC20(name, symbol, decimals_)
    {
        ptToken = _ptToken;
        syToken = _syToken;
    }

    function readTokens() external view returns (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT) {
        return (IStandardizedYield(syToken), IPPrincipalToken(ptToken), IPYieldToken(address(0)));
    }

    function setExpired(bool _isExpired) external {
        s_isExpired = _isExpired;
    }

    function isExpired() external view returns (bool) {
        return s_isExpired;
    }
}
