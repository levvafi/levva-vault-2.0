// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/Extensions/ERC4626Upgradeable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {
    TokenInput,
    ApproxParams,
    LimitOrderData,
    SwapData,
    TokenOutput
} from "@pendle/core-v2/contracts/interfaces/IPAllActionTypeV3.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Asserts} from "../../libraries/Asserts.sol";

contract PendleAdapter is IERC165, IAdapter, Ownable2Step {
    using SafeERC20 for IERC20;
    using Asserts for address;

    address private immutable s_pendleRouter;

    mapping(address vault => mapping(address market => bool available)) private s_availableMarkets;

    event MarketAvailabilityUpdated(address indexed vault, address indexed market, bool available);

    error PendleAdapter__MarketNotAvailable();
    error PendleAdapter__SlippageProtection();

    constructor(address pendleRouter, address initialOwner) Ownable(initialOwner) {
        pendleRouter.assertNotZeroAddress();

        s_pendleRouter = pendleRouter;
    }

    /// @notice Get the identifier of adapter
    function getAdapterId() external pure returns (bytes4) {
        return 0x94dfa9d4; // bytes4(keccak256("PendleAdapter"))
    }

    /// @notice Implementation of ERC165, supports IAdapter and IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAdapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Add pendle market to the list of available markets for the vault
    /// @param vault vault address
    /// @param market pendle market address
    /// @param add true if market is available, false if not
    /// @dev Only the owner can call this function
    function addMarket(address vault, address market, bool add) external onlyOwner {
        vault.assertNotZeroAddress();
        market.assertNotZeroAddress();

        s_availableMarkets[vault][market] = add;

        emit MarketAvailabilityUpdated(vault, market, add);
    }

    function swapExactTokenForPt(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minPtOut
    ) external returns (bytes memory result) {
        _ensureMarketAvailable(market);

        // transfer exact amount of tokenIn from msg.sender to this contract
        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenInput.tokenIn, tokenInput.netTokenIn, "");

        address pendleRouter = s_pendleRouter;
        IERC20(tokenInput.tokenIn).forceApprove(pendleRouter, tokenInput.netTokenIn);

        LimitOrderData memory emptyLimitOrderData;
        (uint256 netPtOut,,) = IPAllActionV3(pendleRouter).swapExactTokenForPt(
            msg.sender, market, minPtOut, approxParams, tokenInput, emptyLimitOrderData
        );

        if (netPtOut < minPtOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    function swapExactPtForToken(address market, address ptToken, uint256 exactPtIn, TokenOutput calldata tokenOut)
        external
        returns (bytes memory result)
    {
        _ensureMarketAvailable(market);

        // transfer exact amount of ptToken from msg.sender to this contract
        IAdapterCallback(msg.sender).adapterCallback(address(this), ptToken, exactPtIn, "");

        address pendleRouter = s_pendleRouter;
        IERC20(ptToken).forceApprove(pendleRouter, exactPtIn);

        LimitOrderData memory emptyLimitOrderData;
        (uint256 netTokenOut,,) = IPAllActionV3(pendleRouter).swapExactPtForToken(
            msg.sender, market, exactPtIn, tokenOut, emptyLimitOrderData
        );

        if (netTokenOut < tokenOut.minTokenOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    function addLiquiditySingleToken(
        address market,
        ApproxParams calldata approxParams,
        TokenInput calldata tokenInput,
        uint256 minLpOut
    ) external returns (bytes memory result) {
        _ensureMarketAvailable(market);

        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenInput.tokenIn, tokenInput.netTokenIn, "");

        address pendleRouter = s_pendleRouter;
        IERC20(tokenInput.tokenIn).forceApprove(pendleRouter, tokenInput.netTokenIn);

        LimitOrderData memory emptyLimitOrderData;
        (uint256 netLpOut,,) = IPAllActionV3(pendleRouter).addLiquiditySingleToken(
            msg.sender, market, minLpOut, approxParams, tokenInput, emptyLimitOrderData
        );

        if (netLpOut < minLpOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    function removeLiquiditySingleToken(
        address market,
        address lpToken,
        uint256 lpAmount,
        TokenOutput calldata tokenOut
    ) external returns (bytes memory result) {
        _ensureMarketAvailable(market);

        IAdapterCallback(msg.sender).adapterCallback(address(this), lpToken, lpAmount, "");

        address pendleRouter = s_pendleRouter;
        IERC20(lpToken).forceApprove(pendleRouter, lpAmount);

        LimitOrderData memory emptyLimitOrderData;
        (uint256 netTokenOut,,) = IPAllActionV3(pendleRouter).removeLiquiditySingleToken(
            msg.sender, market, lpAmount, tokenOut, emptyLimitOrderData
        );

        //double check the output
        if (netTokenOut < tokenOut.minTokenOut) {
            revert PendleAdapter__SlippageProtection();
        }
    }

    function getMarketIsAvailable(address vault, address market) external view returns (bool) {
        return s_availableMarkets[vault][market];
    }

    function _ensureMarketAvailable(address market) private view {
        if (!s_availableMarkets[msg.sender][market]) {
            revert PendleAdapter__MarketNotAvailable();
        }
    }
}
