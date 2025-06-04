// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ILevvaPool} from "../../contracts/adapters/levvaPool/interfaces/ILevvaPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LevvaPoolMock {
    ILevvaPool.Mode public mode = ILevvaPool.Mode.LongEmergency;
    ILevvaPool.Position public position;
    address public baseToken;
    address public quoteToken;

    constructor(address _baseToken, address _quoteToken) {
        baseToken = _baseToken;
        quoteToken = _quoteToken;
    }

    function setMode(ILevvaPool.Mode _mode) external {
        mode = _mode;
    }

    function positions(address) external view returns (ILevvaPool.Position memory) {
        return position;
    }

    function setPosition(ILevvaPool.PositionType _type, uint256 _baseAmount, uint256 _quoteAmount) external {
        position = ILevvaPool.Position({
            _type: _type,
            heapPosition: 1,
            discountedBaseAmount: _baseAmount,
            discountedQuoteAmount: _quoteAmount
        });
    }

    function execute(ILevvaPool.CallType call, uint256 amount, int256, uint256, bool, address, uint256)
        external
        payable
    {
        if (call == ILevvaPool.CallType.EmergencyWithdraw) {
            if (mode == ILevvaPool.Mode.LongEmergency) {
                IERC20(quoteToken).transfer(msg.sender, position.discountedQuoteAmount);
            } else if (mode == ILevvaPool.Mode.ShortEmergency) {
                IERC20(baseToken).transfer(msg.sender, position.discountedBaseAmount);
            } else {
                revert("Not emergency mode");
            }

            delete position;
        } else if (call == ILevvaPool.CallType.DepositBase) {
            IERC20(baseToken).transferFrom(msg.sender, address(this), amount);
        } else if (call == ILevvaPool.CallType.DepositQuote) {
            IERC20(quoteToken).transferFrom(msg.sender, address(this), amount);
        }
    }
}
