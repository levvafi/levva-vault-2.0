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
        address[] memory coins = _getCurveNgPoolCoins(curvePool);
        return _addLiquidityNgPool(curvePool, coins, amounts, minMintAmount);
    }

    function addLiquidityNgAllExcept(address curvePool, uint256[] calldata exceptAmounts, uint256 minMintAmount)
        external
        returns (uint256)
    {
        address[] memory coins = _getCurveNgPoolCoins(curvePool);

        uint256 coinsLength = coins.length;
        if (coinsLength != exceptAmounts.length) revert WrongInput();

        uint256[] memory amounts = new uint256[](coinsLength);
        for (uint256 i; i < coinsLength;) {
            amounts[i] = IERC20(coins[i]).balanceOf(msg.sender) - exceptAmounts[i];
            unchecked {
                ++i;
            }
        }

        return _addLiquidityNgPool(curvePool, coins, amounts, minMintAmount);
    }

    function removeLiquidityNg(address curvePool, uint256 amount, uint256[] calldata minAmounts)
        external
        returns (uint256[] memory)
    {
        _verifyCurveNgPool(curvePool);
        return _removeLiquidityNg(curvePool, amount, minAmounts);
    }

    function removeLiquidityNgAllExcept(address curvePool, uint256 except, uint256[] calldata minAmounts)
        external
        returns (uint256[] memory)
    {
        _verifyCurveNgPool(curvePool);
        uint256 amount = IERC20(curvePool).balanceOf(msg.sender) - except;
        return _removeLiquidityNg(curvePool, amount, minAmounts);
    }

    function addLiquidityTwoCrypto(
        address curvePool,
        uint256[TWO_CRYPTO_COINS_COUNT] calldata amounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        address[TWO_CRYPTO_COINS_COUNT] memory coins = _getTwoCryptoPoolCoins(curvePool);
        return _addLiquidityTwoCrypto(curvePool, coins, amounts, minMintAmount);
    }

    function addLiquidityTwoCryptoAllExcept(
        address curvePool,
        uint256[TWO_CRYPTO_COINS_COUNT] calldata exceptAmounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        address[TWO_CRYPTO_COINS_COUNT] memory coins = _getTwoCryptoPoolCoins(curvePool);

        uint256[TWO_CRYPTO_COINS_COUNT] memory amounts;
        for (uint256 i; i < TWO_CRYPTO_COINS_COUNT;) {
            amounts[i] = IERC20(coins[i]).balanceOf(msg.sender) - exceptAmounts[i];
            unchecked {
                ++i;
            }
        }

        return _addLiquidityTwoCrypto(curvePool, coins, amounts, minMintAmount);
    }

    function removeLiquidityTwoCrypto(
        address curvePool,
        uint256 amount,
        uint256[TWO_CRYPTO_COINS_COUNT] calldata minAmounts
    ) external returns (uint256[TWO_CRYPTO_COINS_COUNT] memory) {
        _getTwoCryptoPoolCoins(curvePool);
        return _removeLiquidityTwoCrypto(curvePool, amount, minAmounts);
    }

    function removeLiquidityTwoCryptoAllExcept(
        address curvePool,
        uint256 except,
        uint256[TWO_CRYPTO_COINS_COUNT] calldata minAmounts
    ) external returns (uint256[TWO_CRYPTO_COINS_COUNT] memory) {
        _getTwoCryptoPoolCoins(curvePool);
        uint256 amount = IERC20(curvePool).balanceOf(msg.sender) - except;
        return _removeLiquidityTwoCrypto(curvePool, amount, minAmounts);
    }

    function addLiquidityTriCrypto(
        address curvePool,
        uint256[TRI_CRYPTO_COINS_COUNT] calldata amounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        address[TRI_CRYPTO_COINS_COUNT] memory coins = _getTriCryptoPoolCoins(curvePool);
        return _addLiquidityTriCrypto(curvePool, coins, amounts, minMintAmount);
    }

    function addLiquidityTriCryptoAllExcept(
        address curvePool,
        uint256[TRI_CRYPTO_COINS_COUNT] calldata exceptAmounts,
        uint256 minMintAmount
    ) external returns (uint256) {
        address[TRI_CRYPTO_COINS_COUNT] memory coins = _getTriCryptoPoolCoins(curvePool);

        uint256[TRI_CRYPTO_COINS_COUNT] memory amounts;
        for (uint256 i; i < TRI_CRYPTO_COINS_COUNT;) {
            amounts[i] = IERC20(coins[i]).balanceOf(msg.sender) - exceptAmounts[i];
            unchecked {
                ++i;
            }
        }

        return _addLiquidityTriCrypto(curvePool, coins, amounts, minMintAmount);
    }

    function removeLiquidityTriCrypto(
        address curvePool,
        uint256 amount,
        uint256[TRI_CRYPTO_COINS_COUNT] calldata minAmounts
    ) external returns (uint256[TRI_CRYPTO_COINS_COUNT] memory) {
        _getTriCryptoPoolCoins(curvePool);

        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[TRI_CRYPTO_COINS_COUNT] memory amounts =
            ITriCryptoPool(curvePool).remove_liquidity(amount, minAmounts, false, msg.sender);
        emit TriCryptoLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }

    function removeLiquidityTriCryptoAllExcept(
        address curvePool,
        uint256 except,
        uint256[TRI_CRYPTO_COINS_COUNT] calldata minAmounts
    ) external returns (uint256[TRI_CRYPTO_COINS_COUNT] memory) {
        _getTriCryptoPoolCoins(curvePool);

        uint256 amount = IERC20(curvePool).balanceOf(msg.sender) - except;
        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[TRI_CRYPTO_COINS_COUNT] memory amounts =
            ITriCryptoPool(curvePool).remove_liquidity(amount, minAmounts, false, msg.sender);
        emit TriCryptoLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }

    function _addLiquidityNgPool(
        address curvePool,
        address[] memory coins,
        uint256[] memory amounts,
        uint256 minMintAmount
    ) private returns (uint256) {
        uint256 coinsLength = coins.length;
        for (uint256 i; i < coinsLength;) {
            if (amounts[i] != 0) {
                IAdapterCallback(msg.sender).adapterCallback(address(this), coins[i], amounts[i]);
                IERC20(coins[i]).forceApprove(curvePool, amounts[i]);
            }

            unchecked {
                ++i;
            }
        }

        uint256 lpAmount = ICurveNgPool(curvePool).add_liquidity(amounts, minMintAmount, msg.sender);
        emit NgLiquidityAdded(msg.sender, curvePool, coins, amounts, lpAmount);

        return lpAmount;
    }

    function _addLiquidityTwoCrypto(
        address curvePool,
        address[TWO_CRYPTO_COINS_COUNT] memory coins,
        uint256[TWO_CRYPTO_COINS_COUNT] memory amounts,
        uint256 minMintAmount
    ) private returns (uint256) {
        for (uint256 i; i < TWO_CRYPTO_COINS_COUNT;) {
            if (amounts[i] != 0) {
                IAdapterCallback(msg.sender).adapterCallback(address(this), coins[i], amounts[i]);
                IERC20(coins[i]).forceApprove(curvePool, amounts[i]);
            }

            unchecked {
                ++i;
            }
        }

        uint256 lpAmount = ITwoCryptoPool(curvePool).add_liquidity(amounts, minMintAmount, msg.sender);
        emit TwoCryptoLiquidityAdded(msg.sender, curvePool, coins, amounts, lpAmount);

        return lpAmount;
    }

    function _addLiquidityTriCrypto(
        address curvePool,
        address[TRI_CRYPTO_COINS_COUNT] memory coins,
        uint256[TRI_CRYPTO_COINS_COUNT] memory amounts,
        uint256 minMintAmount
    ) private returns (uint256) {
        for (uint256 i; i < TRI_CRYPTO_COINS_COUNT;) {
            if (amounts[i] != 0) {
                IAdapterCallback(msg.sender).adapterCallback(address(this), coins[i], amounts[i]);
                IERC20(coins[i]).forceApprove(curvePool, amounts[i]);
            }
            unchecked {
                ++i;
            }
        }

        uint256 lpAmount = ITriCryptoPool(curvePool).add_liquidity(amounts, minMintAmount, false, msg.sender);
        emit TriCryptoLiquidityAdded(msg.sender, curvePool, coins, amounts, lpAmount);

        return lpAmount;
    }

    function _removeLiquidityNg(address curvePool, uint256 amount, uint256[] calldata minAmounts)
        private
        returns (uint256[] memory)
    {
        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[] memory amounts = ICurveNgPool(curvePool).remove_liquidity(amount, minAmounts, msg.sender);
        emit NgLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }

    function _removeLiquidityTwoCrypto(
        address curvePool,
        uint256 amount,
        uint256[TWO_CRYPTO_COINS_COUNT] calldata minAmounts
    ) private returns (uint256[TWO_CRYPTO_COINS_COUNT] memory) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), curvePool, amount);

        uint256[TWO_CRYPTO_COINS_COUNT] memory amounts =
            ITwoCryptoPool(curvePool).remove_liquidity(amount, minAmounts, msg.sender);
        emit TwoCryptoLiquidityRemoved(msg.sender, curvePool, amount, amounts);

        return amounts;
    }

    function _getCurveNgPoolCoins(address curvePool) private view returns (address[] memory coins) {
        coins = curveNgPoolFactory.get_coins(curvePool);
        if (coins.length == 0) revert UnknownCurvePool(curvePool);
    }

    function _getTwoCryptoPoolCoins(address curvePool)
        private
        view
        returns (address[TWO_CRYPTO_COINS_COUNT] memory coins)
    {
        coins = twoCryptoFactory.get_coins(curvePool);
        if (coins[0] == address(0)) revert UnknownCurvePool(curvePool);
    }

    function _getTriCryptoPoolCoins(address curvePool)
        private
        view
        returns (address[TRI_CRYPTO_COINS_COUNT] memory coins)
    {
        coins = triCryptoFactory.get_coins(curvePool);
        if (coins[0] == address(0)) revert UnknownCurvePool(curvePool);
    }

    function _verifyCurveNgPool(address curvePool) private view {
        if (curveNgPoolFactory.get_n_coins(curvePool) == 0) revert UnknownCurvePool(curvePool);
    }
}
