// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {ICurveNgPoolFactory} from "./interfaces/ICurveNgPoolFactory.sol";
import {ICurveNgPool} from "./interfaces/ICurveNgPool.sol";
import {ITriCryptoPoolFactory} from "./interfaces/ITriCryptoPoolFactory.sol";
import {ITriCryptoPool} from "./interfaces/ITriCryptoPool.sol";
import {ITwoCryptoPoolFactory} from "./interfaces/ITwoCryptoPoolFactory.sol";
import {ITwoCryptoPool} from "./interfaces/ITwoCryptoPool.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";

contract CurvePoolAdapter is AdapterBase {
    using Asserts for address;
    using SafeERC20 for IERC20;

    bytes4 public constant getAdapterId = bytes4(keccak256("CurvePoolAdapter"));
    uint256 private constant TWO_CRYPTO_COINS_COUNT = 2;
    uint256 private constant TRI_CRYPTO_COINS_COUNT = 3;

    ICurveNgPoolFactory public immutable curveNgPoolFactory;
    ITwoCryptoPoolFactory public immutable twoCryptoFactory;
    ITriCryptoPoolFactory public immutable triCryptoFactory;

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
    error UnknownCurvePool(address);

    constructor(address _curveNgPoolFactory, address _twoCryptoFactory, address _triCryptoFactory) {
        _curveNgPoolFactory.assertNotZeroAddress();
        _twoCryptoFactory.assertNotZeroAddress();
        _triCryptoFactory.assertNotZeroAddress();

        curveNgPoolFactory = ICurveNgPoolFactory(_curveNgPoolFactory);
        twoCryptoFactory = ITwoCryptoPoolFactory(_twoCryptoFactory);
        triCryptoFactory = ITriCryptoPoolFactory(_triCryptoFactory);
    }

    function addLiquidityNg(address curvePool, uint256[] calldata amounts, uint256 minMintAmount)
        external
        returns (uint256)
    {
        address[] memory coins = curveNgPoolFactory.get_coins(curvePool);

        uint256 coinsLength = coins.length;
        if (coinsLength == 0) revert UnknownCurvePool(curvePool);
        if (coinsLength != amounts.length) revert WrongInput();

        for (uint256 i; i < coinsLength;) {
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
        if (curveNgPoolFactory.get_n_coins(curvePool) == 0) revert UnknownCurvePool(curvePool);

        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[] memory amounts = ICurveNgPool(curvePool).remove_liquidity(amount, minAmounts, msg.sender);
        emit NgLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }

    function addLiquidityTwoCrypto(
        address curvePool,
        uint256[TWO_CRYPTO_COINS_COUNT] calldata amounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        address[TWO_CRYPTO_COINS_COUNT] memory coins = twoCryptoFactory.get_coins(curvePool);
        if (coins[0] == address(0)) revert UnknownCurvePool(curvePool);

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
        address[TWO_CRYPTO_COINS_COUNT] memory coins = twoCryptoFactory.get_coins(curvePool);
        if (coins[0] == address(0)) revert UnknownCurvePool(curvePool);

        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[TWO_CRYPTO_COINS_COUNT] memory amounts =
            ITwoCryptoPool(curvePool).remove_liquidity(amount, minAmounts, msg.sender);
        emit TwoCryptoLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }

    function addLiquidityTriCrypto(
        address curvePool,
        uint256[TRI_CRYPTO_COINS_COUNT] calldata amounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        address[TRI_CRYPTO_COINS_COUNT] memory coins = triCryptoFactory.get_coins(curvePool);
        if (coins[0] == address(0)) revert UnknownCurvePool(curvePool);

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
        address[TRI_CRYPTO_COINS_COUNT] memory coins = triCryptoFactory.get_coins(curvePool);
        if (coins[0] == address(0)) revert UnknownCurvePool(curvePool);

        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[TRI_CRYPTO_COINS_COUNT] memory amounts =
            ITriCryptoPool(curvePool).remove_liquidity(amount, minAmounts, false, msg.sender);
        emit TriCryptoLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }
}
