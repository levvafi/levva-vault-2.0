// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {ICurveNgPool} from "./interfaces/ICurveNgPool.sol";
import {ITriCryptoPool} from "./interfaces/ITriCryptoPool.sol";
import {ITwoCryptoPool} from "./interfaces/ITwoCryptoPool.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";

contract CurvePoolAdapter is AdapterBase {
    using Asserts for address;
    using SafeERC20 for IERC20;

    bytes4 public constant getAdapterId = bytes4(keccak256("CurvePoolAdapter"));
    uint256 private constant TWO_CRYPTO_COINS_COUNT = 2;
    uint256 private constant TRI_CRYPTO_COINS_COUNT = 3;

    event NgLiquidityAdded(
        address indexed vault, address indexed curvePool, address[] coins, uint256[] amounts, uint256 lpAmount
    );

    event NgLiquidityRemoved(address indexed vault, address indexed curvePool, uint256 amount, uint256[] amounts);

    event TwoCryptoLiquidityAdded(
        address indexed vault,
        address indexed curvePool,
        address[TWO_CRYPTO_COINS_COUNT] coins,
        uint256[TWO_CRYPTO_COINS_COUNT] amounts,
        uint256 lpAmount
    );

    event TwoCryptoLiquidityRemoved(
        address indexed vault, address indexed curvePool, uint256 amount, uint256[TWO_CRYPTO_COINS_COUNT] amounts
    );

    event TriCryptoLiquidityAdded(
        address indexed vault,
        address indexed curvePool,
        address[TRI_CRYPTO_COINS_COUNT] coins,
        uint256[TRI_CRYPTO_COINS_COUNT] amounts,
        uint256 lpAmount
    );

    event TriCryptoLiquidityRemoved(
        address indexed vault, address indexed curvePool, uint256 amount, uint256[TRI_CRYPTO_COINS_COUNT] amounts
    );

    error WrongInput();

    function addLiquidityNg(
        address curvePool,
        address[] calldata coins,
        uint256[] calldata amounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        uint256 amountsLength = amounts.length;
        if (amountsLength != coins.length) revert WrongInput();

        for (uint256 i; i < amountsLength;) {
            IAdapterCallback(msg.sender).adapterCallback(address(this), coins[i], amounts[i]);
            IERC20(coins[i]).forceApprove(curvePool, amounts[i]);
            unchecked {
                ++i;
            }
        }

        uint256 lpAmount = ICurveNgPool(curvePool).add_liquidity(amounts, minMintAmount, msg.sender);
        emit NgLiquidityAdded(msg.sender, curvePool, coins, amounts, lpAmount);

        return lpAmount;
    }

    function removeLiquidityNg(address curvePool, uint256 amount, uint256[] calldata minAmounts)
        external
        returns (uint256[] memory)
    {
        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[] memory amounts = ICurveNgPool(curvePool).remove_liquidity(amount, minAmounts, msg.sender);
        emit NgLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }

    function addLiquidityTwoCrypto(
        address curvePool,
        address[TWO_CRYPTO_COINS_COUNT] calldata coins,
        uint256[TWO_CRYPTO_COINS_COUNT] calldata amounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        for (uint256 i; i < TWO_CRYPTO_COINS_COUNT;) {
            IAdapterCallback(msg.sender).adapterCallback(address(this), coins[i], amounts[i]);
            IERC20(coins[i]).forceApprove(curvePool, amounts[i]);
            unchecked {
                ++i;
            }
        }

        uint256 lpAmount = ITwoCryptoPool(curvePool).add_liquidity(amounts, minMintAmount, msg.sender);
        emit TwoCryptoLiquidityAdded(msg.sender, curvePool, coins, amounts, lpAmount);

        return lpAmount;
    }

    function removeLiquidityTwoCrypto(
        address curvePool,
        uint256 amount,
        uint256[TWO_CRYPTO_COINS_COUNT] calldata minAmounts
    ) external returns (uint256[TWO_CRYPTO_COINS_COUNT] memory) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[TWO_CRYPTO_COINS_COUNT] memory amounts =
            ITwoCryptoPool(curvePool).remove_liquidity(amount, minAmounts, msg.sender);
        emit TwoCryptoLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }

    function addLiquidityTriCrypto(
        address curvePool,
        address[TRI_CRYPTO_COINS_COUNT] calldata coins,
        uint256[TRI_CRYPTO_COINS_COUNT] calldata amounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        for (uint256 i; i < TRI_CRYPTO_COINS_COUNT;) {
            IAdapterCallback(msg.sender).adapterCallback(address(this), coins[i], amounts[i]);
            IERC20(coins[i]).forceApprove(curvePool, amounts[i]);
            unchecked {
                ++i;
            }
        }

        uint256 lpAmount = ITriCryptoPool(curvePool).add_liquidity(amounts, minMintAmount, false, msg.sender);
        emit TriCryptoLiquidityAdded(msg.sender, curvePool, coins, amounts, lpAmount);

        return lpAmount;
    }

    function removeLiquidityTriCrypto(
        address curvePool,
        uint256 amount,
        uint256[TRI_CRYPTO_COINS_COUNT] calldata minAmounts
    ) external returns (uint256[TRI_CRYPTO_COINS_COUNT] memory) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[TRI_CRYPTO_COINS_COUNT] memory amounts =
            ITriCryptoPool(curvePool).remove_liquidity(amount, minAmounts, false, msg.sender);
        emit TriCryptoLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }
}
