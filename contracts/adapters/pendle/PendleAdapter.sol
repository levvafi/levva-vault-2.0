// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/Extensions/ERC4626Upgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";

contract PendleAdapter is Ownable {
    using SafeERC20 for IERC20;

    address private immutable s_pendleRouter;

    mapping(address vault => mapping(address market => bool available)) private s_availableMarkets;

    event MarketAvailabilityUpdated(address indexed vault, address indexed market, bool available);

    error PendleAdapter__MarketNotAvailable();
    error PendleAdapter__ZeroAddress();
    error PendleAdapter__SlippageProtection();

    constructor(address pendleRouter, address initialOwner) Ownable(initialOwner) {
        if (pendleRouter == address(0) || initialOwner == address(0)) {
            revert PendleAdapter__ZeroAddress();
        }

        s_pendleRouter = pendleRouter;
    }

    function addMarket(address vault, address market, bool add) external onlyOwner {
        if (vault == address(0) || market == address(0)) {
            revert PendleAdapter__ZeroAddress();
        }

        s_availableMarkets[vault][market] = add;

        emit MarketAvailabilityUpdated(vault, market, add);
    }

    function swapExactTokenForPt(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minPtOut
    ) external {
        _ensureMarketAvailable(market);

        address pendleRouter = s_pendleRouter;

        IERC20(tokenInput.tokenIn).forceApprove(pendleRouter, tokenInput.netTokenIn);
        (uint256 netPtOut,,) = IPAllActionV3(pendleRouter).swapExactTokenForPt(
            msg.sender, market, minPtOut, approxParams, tokenInput, _createEmptyLimitOrderData()
        );

        if (netPtOut < minPtOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    function swapExactPtForToken(address market, address ptToken, uint256 exactPtIn, TokenOutput calldata tokenOut)
        external
    {
        _ensureMarketAvailable(market);

        address pendleRouter = s_pendleRouter;
        IERC20(ptToken).forceApprove(pendleRouter, exactPtIn);
        (uint256 netTokenOut,,) = IPAllActionV3(pendleRouter).swapExactPtForToken(
            msg.sender, market, exactPtIn, tokenOut, _createEmptyLimitOrderData()
        );

        //double check the output
        if (netTokenOut < tokenOut.minTokenOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    // function addLiquiditySingleToken(address market, address tokenIn, uint256 exactTokenIn, uint256 minLpOut)
    //     external
    // {
    //     _ensureMarketAvailable(market);

    //     address pendleRouter = s_pendleRouter;
    //     IERC20(tokenIn).forceApprove(pendleRouter, exactTokenIn);
    //     (uint256 netLpOut,,) = IPAllActionV3(pendleRouter).addLiquiditySingleToken(
    //         msg.sender,
    //         market,
    //         minLpOut,
    //         _createDefaultApproxParams(),
    //         _createTokenInputSimple(tokenIn, exactTokenIn),
    //         _createEmptyLimitOrderData()
    //     );

    //     //double check the output
    //     if (netLpOut < minLpOut) {
    //         revert PendleAdapter__SlippageProtection();
    //     }
    // }

    // function removeLiquiditySingleToken(
    //     address market,
    //     address lpToken,
    //     uint256 lpAmount,
    //     address tokenOut,
    //     uint256 minTokenOut
    // ) external {
    //     _ensureMarketAvailable(market);

    //     address pendleRouter = s_pendleRouter;
    //     IERC20(lpToken).forceApprove(pendleRouter, lpAmount);
    //     (uint256 netTokenOut,,) = IPAllActionV3(pendleRouter).removeLiquiditySingleToken(
    //         msg.sender, market, lpAmount, _createTokenOutputSimple(tokenOut, minTokenOut), _createEmptyLimitOrderData()
    //     );

    //     //double check the output
    //     if (netTokenOut < minTokenOut) {
    //         revert PendleAdapter__SlippageProtection();
    //     }
    // }

    function _ensureMarketAvailable(address market) private view {
        if (!s_availableMarkets[msg.sender][market]) {
            revert PendleAdapter__MarketNotAvailable();
        }
    }

    function _createEmptyLimitOrderData() private pure returns (LimitOrderData memory) {}
}
