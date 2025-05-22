// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {AdapterBase} from "../AdapterBase.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {IMultiAssetVault} from "../../interfaces/IMultiAssetVault.sol";
import {IEulerPriceOracle} from "../../interfaces/IEulerPriceOracle.sol";
import {ILevvaPool} from "./ILevvaPool.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {FP96} from "./FP96.sol";

/// @title Adapter for interaction with Levva pools (Marginly protocol)
/// @notice Should be deployed for each vault
contract LevvaPoolAdapter is AdapterBase, IExternalPositionAdapter {
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("LevvaPoolAdapter"));

    using FP96 for FP96.FixedPoint;
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 private constant SECONDS_IN_YEAR_X96 = 2500250661360148260042022567123353600;
    uint256 private constant X96_ONE = 2 ** 96;
    uint24 private constant ONE = 1e6;

    address private immutable i_vault;
    address[] private s_pools;
    mapping(address => uint256) private s_poolPosition;

    error LevvaPoolAdapter__NotAuthorized();
    error LevvaPoolAdapter__OracleNotExists(address base, address quote);
    error LevvaPoolAdapter__WrongLevvaPoolMode();
    error LevvaPoolAdapter__NotSupported();

    constructor(address vault) {
        vault.assertNotZeroAddress();
        i_vault = vault;
    }

    modifier onlyVault() {
        _onlyVault();
        _;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IExternalPositionAdapter).interfaceId;
    }

    /// @notice Deposits an amount into a Marginly pool
    /// @param asset The asset to deposit
    /// @param amount The amount to deposit
    /// @param positionAmount Position amount
    /// @param pool The pool to deposit into
    /// @param limitPriceX96 The limit price for the position
    /// @param swapCallData The swap call data
    function deposit(
        address asset,
        uint256 amount,
        int256 positionAmount,
        address pool,
        uint256 limitPriceX96,
        uint256 swapCallData
    ) external onlyVault {
        address quoteToken = ILevvaPool(pool).quoteToken();
        ILevvaPool.CallType callType =
            asset == quoteToken ? ILevvaPool.CallType.DepositQuote : ILevvaPool.CallType.DepositBase;

        //Both token deposits not supported
        ILevvaPool.Position memory position = ILevvaPool(pool).positions(address(this));
        if (position._type == ILevvaPool.PositionType.Lend) {
            if (position.discountedBaseAmount != 0) {
                if (callType == ILevvaPool.CallType.DepositQuote) revert LevvaPoolAdapter__NotSupported();
            } else {
                if (callType == ILevvaPool.CallType.DepositBase) revert LevvaPoolAdapter__NotSupported();
            }
        }

        if (callType == ILevvaPool.CallType.DepositQuote && positionAmount < 0) {
            // depositQuote and long
            _assertOracleExists(quoteToken, IMultiAssetVault(msg.sender).asset());
        } else if (callType == ILevvaPool.CallType.DepositBase && positionAmount < 0) {
            // depositBase and short
            _assertOracleExists(ILevvaPool(pool).baseToken(), IMultiAssetVault(msg.sender).asset());
        }

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, amount);

        IERC20(asset).forceApprove(address(pool), amount);
        ILevvaPool(pool).execute(callType, amount, positionAmount, limitPriceX96, false, address(0), swapCallData);

        _addPool(pool);
    }

    ///@notice Opens a long position
    ///@param amount The amount to open a long position
    ///@param pool The pool to open a long position in
    ///@param limitPriceX96 The limit price for the position
    ///@param swapCallData The swap call data
    function long(uint256 amount, address pool, uint256 limitPriceX96, uint256 swapCallData) external onlyVault {
        ILevvaPool(pool).execute(
            ILevvaPool.CallType.Long, amount, int256(0), limitPriceX96, false, address(0), swapCallData
        );

        // long - quoteToken in debt, check oracle for quoteToken
        _assertOracleExists(ILevvaPool(pool).quoteToken(), IMultiAssetVault(msg.sender).asset());
    }

    ///@notice Opens a short position
    ///@param amount The amount to open a short position
    ///@param pool The pool to open a short position in
    ///@param limitPriceX96 The limit price for the position
    ///@param swapCallData The swap call data
    function short(uint256 amount, address pool, uint256 limitPriceX96, uint256 swapCallData) external onlyVault {
        ILevvaPool(pool).execute(
            ILevvaPool.CallType.Short, amount, int256(0), limitPriceX96, false, address(0), swapCallData
        );

        // short - baseToken in debt, check oracle for baseToken
        _assertOracleExists(ILevvaPool(pool).baseToken(), IMultiAssetVault(msg.sender).asset());
    }

    ///@notice Closes a position
    ///@param pool The pool to close a position in
    ///@param limitPriceX96 The limit price for the position
    ///@param swapCallData The swap call data
    function closePosition(address pool, uint256 limitPriceX96, uint256 swapCallData) external onlyVault {
        ILevvaPool(pool).execute(
            ILevvaPool.CallType.ClosePosition, 0, int256(0), limitPriceX96, false, address(0), swapCallData
        );
    }

    /// @notice Withdraws an amount from pool
    /// @param asset The asset to withdraw
    /// @param amount The amount to withdraw
    /// @param pool The pool to withdraw from
    function withdraw(address asset, uint256 amount, address pool) external onlyVault returns (uint256 amountOut) {
        _ensureIsValidAsset(asset);
        ILevvaPool.CallType callType = ILevvaPool(pool).quoteToken() == asset
            ? ILevvaPool.CallType.WithdrawQuote
            : ILevvaPool.CallType.WithdrawBase;

        ILevvaPool(pool).execute(callType, amount, int256(0), 0, false, address(0), 0);
        amountOut = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransfer(msg.sender, amountOut);

        ILevvaPool.Position memory position = ILevvaPool(pool).positions(address(this));
        if (position._type == ILevvaPool.PositionType.Uninitialized) {
            _removePool(pool);
        }
    }

    /// @notice Withdraws an amount when pool in emergency mode
    /// @param pool The pool to withdraw from
    function emergencyWithdraw(address pool) external onlyVault {
        ILevvaPool.Position memory position = ILevvaPool(pool).positions(address(this));
        ILevvaPool.Mode mode = ILevvaPool(pool).mode();

        IERC20 asset;
        if (mode == ILevvaPool.Mode.ShortEmergency) {
            if (position._type == ILevvaPool.PositionType.Short) {
                _removePool(pool);
                return;
            }
            asset = IERC20(ILevvaPool(pool).baseToken());
        } else if (mode == ILevvaPool.Mode.LongEmergency) {
            if (position._type == ILevvaPool.PositionType.Long) {
                _removePool(pool);
                return;
            }
            asset = IERC20(ILevvaPool(pool).quoteToken());
        } else {
            revert LevvaPoolAdapter__WrongLevvaPoolMode();
        }

        _ensureIsValidAsset(address(asset));

        ILevvaPool(pool).execute(ILevvaPool.CallType.EmergencyWithdraw, 0, int256(0), 0, false, address(0), 0);

        asset.safeTransfer(msg.sender, asset.balanceOf(address(this)));

        position = ILevvaPool(pool).positions(address(this));
        if (position._type == ILevvaPool.PositionType.Uninitialized) {
            _removePool(pool);
        }
    }

    /// @notice Returns managed assets by the vault in adapter Protocol
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        uint256 length = s_pools.length;
        assets = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i; i < length;) {
            ILevvaPool pool = ILevvaPool(s_pools[i]);
            ILevvaPool.Position memory position = pool.positions(address(this));

            if (position._type == ILevvaPool.PositionType.Short || position.discountedBaseAmount == 0) {
                //isQuote
                assets[i] = pool.quoteToken();
                amounts[i] = _estimateCollateral(pool, true, position.discountedQuoteAmount);
            } else {
                assets[i] = pool.baseToken();
                amounts[i] = _estimateCollateral(pool, false, position.discountedBaseAmount);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns debt assets managed by the vault in adapter Protocol
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        uint256 length = s_pools.length;
        assets = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i; i < length;) {
            ILevvaPool pool = ILevvaPool(s_pools[i]);
            ILevvaPool.Position memory position = pool.positions(address(this));

            if (position._type == ILevvaPool.PositionType.Long) {
                assets[i] = pool.quoteToken();
                amounts[i] = _estimateDebtCoeff(pool, true).mul(position.discountedQuoteAmount);
            } else if (position._type == ILevvaPool.PositionType.Short) {
                assets[i] = pool.baseToken();
                amounts[i] = _estimateDebtCoeff(pool, false).mul(position.discountedBaseAmount);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the vault address
    function getVault() external view returns (address) {
        return i_vault;
    }

    /// @notice Returns all connected pools
    function getPools() external view returns (address[] memory pools) {
        return s_pools;
    }

    function _onlyVault() private view {
        if (msg.sender != i_vault) {
            revert LevvaPoolAdapter__NotAuthorized();
        }
    }

    function _addPool(address pool) private {
        if (s_poolPosition[pool] != 0) {
            return;
        }

        s_pools.push(pool);
        s_poolPosition[pool] = s_pools.length;
    }

    function _removePool(address pool) private {
        uint256 poolPosition = s_poolPosition[pool];
        if (poolPosition == 0) {
            return;
        }

        uint256 poolIndex = poolPosition - 1;
        uint256 poolsLastIndex = s_pools.length - 1;

        if (poolIndex != poolsLastIndex) {
            s_pools[poolIndex] = s_pools[poolsLastIndex];
        }

        s_pools.pop();
        delete s_poolPosition[pool];
    }

    /// @dev A little modified MarginlyPool.accruedInterest() function
    /// @dev https://github.com/eq-lab/marginly/blob/main/packages/contracts/contracts/MarginlyPool.sol#L1019
    /// @dev Instead of calling MarginlyPool.reinit() we make calculations on our side
    /// @dev Reinit simulation without margin calls
    function _estimateCollateral(ILevvaPool pool, bool isQuote, uint256 discountedCollateral)
        private
        view
        returns (uint256)
    {
        uint256 secondsPassed = block.timestamp - pool.lastReinitTimestampSeconds();
        if (secondsPassed == 0) {
            if (isQuote) {
                return pool.quoteCollateralCoeff().mul(discountedCollateral)
                    - pool.quoteDelevCoeff().mul(pool.discountedBaseDebt());
            } else {
                return pool.baseCollateralCoeff().mul(discountedCollateral)
                    - pool.baseDelevCoeff().mul(pool.discountedQuoteDebt());
            }
        }

        ILevvaPool.MarginlyParams memory params = pool.params();

        FP96.FixedPoint memory secondsInYear = FP96.FixedPoint({inner: SECONDS_IN_YEAR_X96});
        FP96.FixedPoint memory interestRate = FP96.fromRatio(params.interestRate, ONE);

        if (isQuote) {
            FP96.FixedPoint memory quoteCollateralCoeff = pool.quoteCollateralCoeff();

            uint256 realQuoteDebt;
            {
                //stack too deep
                FP96.FixedPoint memory systemLeverage = FP96.FixedPoint({inner: pool.systemLeverage().longX96});
                FP96.FixedPoint memory onePlusIR = interestRate.mul(systemLeverage).div(secondsInYear).add(FP96.one());

                // AR(dt) =  (1 + ir)^dt
                FP96.FixedPoint memory accruedRateDt = FP96.powTaylor(onePlusIR, secondsPassed);
                uint256 realQuoteDebtPrev = pool.quoteDebtCoeff().mul(pool.discountedQuoteDebt());
                realQuoteDebt = accruedRateDt.sub(FP96.one()).mul(realQuoteDebtPrev);
            }
            uint256 delevPart = pool.quoteDelevCoeff().mul(pool.discountedBaseDebt());
            uint256 realQuoteCollateral = quoteCollateralCoeff.mul(pool.discountedQuoteCollateral()) - delevPart;

            FP96.FixedPoint memory factor = FP96.one().add(FP96.fromRatio(realQuoteDebt, realQuoteCollateral));

            //quoteCollateralCoeff.mul(disQuoteCollateral).sub(quoteDelevCoeff.mul(disBaseDebt));
            return quoteCollateralCoeff.mul(factor).mul(discountedCollateral) - delevPart;
        } else {
            FP96.FixedPoint memory baseCollateralCoeff = pool.baseCollateralCoeff();

            uint256 realBaseDebt;
            {
                //stack too deep
                FP96.FixedPoint memory systemLeverage = FP96.FixedPoint({inner: pool.systemLeverage().shortX96});
                FP96.FixedPoint memory onePlusIR = interestRate.mul(systemLeverage).div(secondsInYear).add(FP96.one());

                // AR(dt) =  (1 + ir)^dt
                FP96.FixedPoint memory accruedRateDt = FP96.powTaylor(onePlusIR, secondsPassed);
                uint256 realBaseDebtPrev = pool.baseDebtCoeff().mul(pool.discountedBaseDebt());
                realBaseDebt = accruedRateDt.sub(FP96.one()).mul(realBaseDebtPrev);
            }
            uint256 delevPart = pool.baseDelevCoeff().mul(pool.discountedQuoteDebt());
            uint256 realBaseCollateral = baseCollateralCoeff.mul(pool.discountedBaseCollateral()) - delevPart;

            FP96.FixedPoint memory factor = FP96.one().add(FP96.fromRatio(realBaseDebt, realBaseCollateral));

            //baseCollateralCoeff.mul(disBaseCollateral).sub(baseDelevCoeff.mul(disQuoteDebt));
            return baseCollateralCoeff.mul(factor).mul(discountedCollateral) - delevPart;
        }
    }

    function _estimateDebtCoeff(ILevvaPool pool, bool isLong) private view returns (FP96.FixedPoint memory) {
        uint256 secondsPassed = block.timestamp - pool.lastReinitTimestampSeconds();
        if (secondsPassed == 0) {
            return isLong ? pool.quoteDebtCoeff() : pool.baseDebtCoeff();
        }

        ILevvaPool.MarginlyParams memory params = pool.params();

        FP96.FixedPoint memory secondsInYear = FP96.FixedPoint({inner: SECONDS_IN_YEAR_X96});
        FP96.FixedPoint memory onePlusFee = FP96.fromRatio(params.fee, ONE).div(secondsInYear).add(FP96.one());
        FP96.FixedPoint memory interestRate = FP96.fromRatio(params.interestRate, ONE);
        FP96.FixedPoint memory feeDt = FP96.powTaylor(onePlusFee, secondsPassed);

        if (isLong) {
            FP96.FixedPoint memory systemLeverage = FP96.FixedPoint({inner: pool.systemLeverage().longX96});
            FP96.FixedPoint memory onePlusIR = interestRate.mul(systemLeverage).div(secondsInYear).add(FP96.one());

            // AR(dt) =  (1 + ir)^dt
            FP96.FixedPoint memory accruedRateDt = FP96.powTaylor(onePlusIR, secondsPassed);

            // quoteDebtCoeff = quoteDebtCoeffPrev * accruedRateDt * feeDt
            return pool.quoteDebtCoeff().mul(accruedRateDt).mul(feeDt);
        } else {
            FP96.FixedPoint memory systemLeverage = FP96.FixedPoint({inner: pool.systemLeverage().shortX96});
            FP96.FixedPoint memory onePlusIR = interestRate.mul(systemLeverage).div(secondsInYear).add(FP96.one());

            // AR(dt) =  (1 + ir)^dt
            FP96.FixedPoint memory accruedRateDt = FP96.powTaylor(onePlusIR, secondsPassed);

            // baseDebtCoeff = baseDebtCoeffPrev * accruedRateDt * feeDt
            return pool.baseDebtCoeff().mul(accruedRateDt).mul(feeDt);
        }
    }

    function _assertOracleExists(address base, address quote) internal view {
        IEulerPriceOracle eulerOracle = IEulerPriceOracle(IMultiAssetVault(msg.sender).oracle());
        if (
            _callOracle(eulerOracle, _getOneToken(base), base, quote) == 0
                && _callOracle(eulerOracle, _getOneToken(quote), quote, base) == 0
        ) revert LevvaPoolAdapter__OracleNotExists(base, quote);
    }

    function _getOneToken(address token) private view returns (uint256) {
        return 10 ** IERC20Metadata(token).decimals();
    }

    function _callOracle(IEulerPriceOracle eulerOracle, uint256 baseAmount, address baseToken, address quoteToken)
        private
        view
        returns (uint256)
    {
        return eulerOracle.getQuote(baseAmount, baseToken, quoteToken);
    }
}
