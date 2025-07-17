// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ILevvaPool} from "../../contracts/adapters/levvaPool/interfaces/ILevvaPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LevvaPoolMock {
    using Math for uint256;

    ILevvaPool.Mode public mode = ILevvaPool.Mode.LongEmergency;
    ILevvaPool.Position public position;
    address public baseToken;
    address public quoteToken;
    uint256 public basePriceX96;
    uint256 public lastReinitTimestampSeconds;

    uint256 public immutable baseCollateralCoeff = 1 << 96;
    uint256 public immutable quoteCollateralCoeff = 1 << 96;
    uint256 public immutable baseDebtCoeff = 1 << 96;
    uint256 public immutable quoteDebtCoeff = 1 << 96;
    uint256 public immutable baseDelevCoeff;
    uint256 public immutable quoteDelevCoeff = 1 << 96;

    error AlreadyInMainnet();
    error WrongSetup();

    constructor(address _baseToken, address _quoteToken) {
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        lastReinitTimestampSeconds = block.timestamp;
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

    function setBasePriceX96(uint256 _basePriceX96) external {
        basePriceX96 = _basePriceX96;
    }

    function execute(ILevvaPool.CallType call, uint256 amount, int256, uint256, bool flag, address, uint256)
        external
        payable
    {
        lastReinitTimestampSeconds = block.timestamp;

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
        } else if (call == ILevvaPool.CallType.ClosePosition) {
            if (!flag) revert AlreadyInMainnet();

            if (position._type == ILevvaPool.PositionType.Long) {
                uint256 withdrawalAmount =
                    position.discountedBaseAmount - position.discountedQuoteAmount.mulDiv(1 << 96, basePriceX96);
                IERC20(baseToken).transfer(msg.sender, withdrawalAmount);
            } else if (position._type == ILevvaPool.PositionType.Short) {
                uint256 withdrawalAmount =
                    position.discountedQuoteAmount - position.discountedBaseAmount.mulDiv(basePriceX96, 1 << 96);
                IERC20(quoteToken).transfer(msg.sender, withdrawalAmount);
            } else {
                revert WrongSetup();
            }
            delete position;
        } else if (call == ILevvaPool.CallType.SellCollateral) {
            uint256 withdrawalAmount;
            address token;

            if (position._type == ILevvaPool.PositionType.Long) {
                position.discountedQuoteAmount =
                    position.discountedBaseAmount.mulDiv(basePriceX96, 1 << 96) - position.discountedQuoteAmount;
                position.discountedBaseAmount = 0;
                withdrawalAmount = position.discountedQuoteAmount;
                token = quoteToken;
            } else if (position._type == ILevvaPool.PositionType.Short) {
                position.discountedBaseAmount =
                    position.discountedQuoteAmount.mulDiv(1 << 96, basePriceX96) - position.discountedBaseAmount;
                position.discountedQuoteAmount = 0;
                withdrawalAmount = position.discountedBaseAmount;
                token = baseToken;
            } else {
                revert WrongSetup();
            }

            position._type = ILevvaPool.PositionType.Lend;

            if (flag) {
                IERC20(token).transfer(msg.sender, withdrawalAmount);
                delete position;
            }
        } else {
            revert AlreadyInMainnet();
        }
    }

    function discountedBaseCollateral() external view returns (uint256) {
        return position._type != ILevvaPool.PositionType.Short ? position.discountedBaseAmount : 0;
    }

    function discountedQuoteCollateral() external view returns (uint256) {
        return position._type != ILevvaPool.PositionType.Long ? position.discountedQuoteAmount : 0;
    }

    function discountedBaseDebt() external view returns (uint256) {
        return position._type == ILevvaPool.PositionType.Short ? position.discountedBaseAmount : 0;
    }

    function discountedQuoteDebt() external view returns (uint256) {
        return position._type == ILevvaPool.PositionType.Long ? position.discountedQuoteAmount : 0;
    }
}
