// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;
// Derived in part from Uniswap V3 Core UniswapV3Pool.sol; modified by the Abyss project
// on 2026-08-17, 2026-08-18, and 2026-08-19: split and adapt swap execution for quote-only
// fees, checked fee-growth accounting, Abyss callbacks, and oracle-write policy.

import { AbyssPoolBase } from "./AbyssPoolBase.sol";
import { QuoteFeeMath } from "../libraries/QuoteFeeMath.sol";
import { PoolProfile } from "../types/AbyssTypes.sol";
import { LowGasSafeMath } from "./v3/libraries/LowGasSafeMath.sol";
import { SafeCast } from "./v3/libraries/SafeCast.sol";
import { TickMath } from "./v3/libraries/TickMath.sol";
import { TickBitmap } from "./v3/libraries/TickBitmap.sol";
import { Tick } from "./v3/libraries/Tick.sol";
import { Oracle } from "./v3/libraries/Oracle.sol";
import { LiquidityMath } from "./v3/libraries/LiquidityMath.sol";
import { SwapMath } from "./v3/libraries/SwapMath.sol";
import { FullMath } from "./v3/libraries/FullMath.sol";
import { FixedPoint128 } from "./v3/libraries/FixedPoint128.sol";
import { TransferHelper } from "./v3/libraries/TransferHelper.sol";
import { IUniswapV3SwapCallback } from "./v3/interfaces/callback/IUniswapV3SwapCallback.sol";

abstract contract AbyssQuotePoolBase is AbyssPoolBase {
    error PaidQuoteSwapNoProgress();

    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using TickBitmap for mapping(int16 => uint256);
    using Tick for mapping(int24 => Tick.Info);
    using Oracle for Oracle.Observation[65_535];

    struct QuoteSwapParams {
        address recipient;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        bytes data;
    }

    constructor(PoolProfile expectedProfile) AbyssPoolBase(expectedProfile) { }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override noDelegateCall returns (int256 amount0, int256 amount1) {
        return _quoteSwap(
            QuoteSwapParams(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, data)
        );
    }

    function _quoteSwap(QuoteSwapParams memory p) private returns (int256 amount0, int256 amount1) {
        if (p.amountSpecified == 0) revert InvalidInput();
        Slot0 memory slot0Start = slot0;
        if (!slot0Start.unlocked) revert PoolLocked();
        if (p.zeroForOne
                ? p.sqrtPriceLimitX96 >= slot0Start.sqrtPriceX96
                    || p.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO
                : p.sqrtPriceLimitX96 <= slot0Start.sqrtPriceX96
                    || p.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) revert InvalidInput();

        slot0.unlocked = false;
        uint32 time = _blockTimestamp();
        _beforeSwap(time, slot0Start.tick, liquidity);
        SwapCache memory cache;
        cache.liquidityStart = liquidity;
        cache.blockTimestamp = time;
        cache.feeProtocol = slot0Start.feeProtocol & 0x0f;
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: p.amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: quoteIsToken0 ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            protocolFee: 0,
            liquidity: cache.liquidityStart
        });

        _runQuoteSteps(p, state, cache);
        if (state.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = observations.write(
                slot0Start.observationIndex,
                time,
                slot0Start.tick,
                cache.liquidityStart,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext
            );
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) =
                (state.sqrtPriceX96, state.tick, observationIndex, observationCardinality);
        } else {
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }
        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;
        if (quoteIsToken0) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            protocolFees.token0 = _addProtocolFee(protocolFees.token0, state.protocolFee);
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            protocolFees.token1 = _addProtocolFee(protocolFees.token1, state.protocolFee);
        }

        (amount0, amount1) = p.zeroForOne == (p.amountSpecified > 0)
            ? (p.amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, p.amountSpecified - state.amountSpecifiedRemaining);
        int256 amountOut = p.zeroForOne ? amount1 : amount0;
        if (amountOut < 0) {
            TransferHelper.safeTransfer(
                p.zeroForOne ? token1 : token0, p.recipient, _negativeMagnitude(amountOut)
            );
        }
        uint256 balanceBefore = _inputBalance(p.zeroForOne);
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, p.data);
        if (
            balanceBefore.add(uint256(p.zeroForOne ? amount0 : amount1))
                > _inputBalance(p.zeroForOne)
        ) {
            revert PaymentFailed();
        }
        emit Swap(
            msg.sender,
            p.recipient,
            amount0,
            amount1,
            state.sqrtPriceX96,
            state.liquidity,
            state.tick
        );
        slot0.unlocked = true;
    }

    function _runQuoteSteps(
        QuoteSwapParams memory p,
        SwapState memory state,
        SwapCache memory cache
    ) private {
        bool exactInput = p.amountSpecified > 0;
        bool quoteIsInput = p.zeroForOne == quoteIsToken0;
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != p.sqrtPriceLimitX96) {
            StepComputations memory step;
            step.sqrtPriceStartX96 = state.sqrtPriceX96;
            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick, tickSpacing, p.zeroForOne
            );
            if (step.tickNext < TickMath.MIN_TICK) step.tickNext = TickMath.MIN_TICK;
            else if (step.tickNext > TickMath.MAX_TICK) step.tickNext = TickMath.MAX_TICK;
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);
            uint160 target = (p.zeroForOne
                    ? step.sqrtPriceNextX96 < p.sqrtPriceLimitX96
                    : step.sqrtPriceNextX96 > p.sqrtPriceLimitX96)
                ? p.sqrtPriceLimitX96
                : step.sqrtPriceNextX96;

            int256 curveRemaining = state.amountSpecifiedRemaining;
            if (!quoteIsInput && !exactInput) {
                (uint256 grossRequired,) = QuoteFeeMath.grossFromNet(
                    _negativeMagnitude(state.amountSpecifiedRemaining), fee
                );
                // Net exact output may fit the signed API domain while its gross curve amount
                // does not. The price limit and available liquidity still bound this step.
                curveRemaining = grossRequired > uint256(type(int256).max)
                    ? type(int256).min
                    : -grossRequired.toInt256();
            }
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) =
                SwapMath.computeSwapStep(
                    state.sqrtPriceX96,
                    target,
                    state.liquidity,
                    curveRemaining,
                    quoteIsInput ? fee : 0
                );

            uint256 traderAmountIn = step.amountIn;
            uint256 traderAmountOut = step.amountOut;
            if (quoteIsInput) {
                traderAmountIn += step.feeAmount;
            } else {
                // With zero curve fee, SwapMath classifies exact-input rounding residue as
                // feeAmount. It remains trader input, not quote fee, and must consume the
                // specified amount before feeAmount is replaced by the output-denominated fee.
                if (exactInput) traderAmountIn += step.feeAmount;
                (traderAmountOut, step.feeAmount) = QuoteFeeMath.netFromGross(step.amountOut, fee);
            }
            if (step.feeAmount > 0 && step.amountIn == 0 && step.amountOut == 0) {
                revert PaidQuoteSwapNoProgress();
            }
            if (exactInput) {
                state.amountSpecifiedRemaining -= traderAmountIn.toInt256();
                state.amountCalculated = state.amountCalculated.sub(traderAmountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += traderAmountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add(traderAmountIn.toInt256());
            }

            if (cache.feeProtocol != 0) {
                uint256 protocolStepFee = step.feeAmount / cache.feeProtocol;
                step.feeAmount -= protocolStepFee;
                state.protocolFee = _addProtocolFee(state.protocolFee, protocolStepFee);
            }
            if (state.liquidity != 0) {
                // Revert before a full Q128 growth cycle can erase backed LP ownership.
                state.feeGrowthGlobalX128 += FullMath.mulDiv(
                    step.feeAmount, FixedPoint128.Q128, state.liquidity
                );
            }

            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) =
                            observations.observeSingle(
                                cache.blockTimestamp,
                                0,
                                slot0.tick,
                                slot0.observationIndex,
                                cache.liquidityStart,
                                slot0.observationCardinality
                            );
                        cache.computedLatestObservation = true;
                    }
                    int128 liquidityNet = ticks.cross(
                        step.tickNext,
                        quoteIsToken0 ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128,
                        quoteIsToken0 ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128,
                        cache.secondsPerLiquidityCumulativeX128,
                        cache.tickCumulative,
                        cache.blockTimestamp
                    );
                    if (p.zeroForOne) liquidityNet = -liquidityNet;
                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }
                state.tick = p.zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }
    }

    function _validateFlashPayments(uint256 paid0, uint256 paid1) internal view override {
        if (quoteIsToken0 ? paid1 != 0 : paid0 != 0) revert InvalidInput();
    }

    function _inputBalance(bool zeroForOne) private view returns (uint256) {
        return zeroForOne ? balance0() : balance1();
    }

    function _negativeMagnitude(int256 value) private pure returns (uint256) {
        return uint256(-(value + 1)) + 1;
    }
}
