// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { AbyssPoolBase } from "./AbyssPoolBase.sol";
import { Oracle } from "./v3/libraries/Oracle.sol";
import { TruncatedOracle } from "../libraries/TruncatedOracle.sol";
import { IAbyssFactory } from "../interfaces/IAbyssFactory.sol";
import { PoolProfile } from "../types/AbyssTypes.sol";

abstract contract AbyssOraclePoolBase is AbyssPoolBase {
    using Oracle for Oracle.Observation[65_535];

    int24 internal immutable maxAbsTickMove;
    uint16 internal immutable truncatedCardinalityCap;

    Oracle.Observation[65_535] internal _truncatedObservations;
    uint16 internal truncatedObservationIndex;
    uint16 internal truncatedObservationCardinality;
    uint16 internal truncatedObservationCardinalityNext;
    int24 internal truncatedTick;
    uint64 internal truncatedLastBlock;

    constructor(PoolProfile expectedProfile) AbyssPoolBase(expectedProfile) {
        (uint24 cap, uint16 cardinality) = IAbyssFactory(factory).oracleConfigs(_oracleConfigId);
        // Factory registration bounds cap to TickMath.MAX_TICK, which fits int24.
        maxAbsTickMove = int24(cap);
        truncatedCardinalityCap = cardinality;
    }

    function observeTruncated(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        )
    {
        return _truncatedObservations.observe(
            _blockTimestamp(),
            secondsAgos,
            truncatedTick,
            truncatedObservationIndex,
            liquidity,
            truncatedObservationCardinality
        );
    }

    function _afterInitialize(uint32 time, int24 tick) internal override {
        (truncatedObservationCardinality, truncatedObservationCardinalityNext) =
            _truncatedObservations.initialize(time);
        truncatedTick = TruncatedOracle.normalizeTick(tick, quoteIsToken0);
        // uint64 block numbers outlive any plausible EVM chain lifetime.
        truncatedLastBlock = uint64(block.number);
    }

    function _afterIncreaseObservationCardinalityNext(uint16 requested) internal override {
        if (requested > truncatedCardinalityCap) requested = truncatedCardinalityCap;
        truncatedObservationCardinalityNext =
            _truncatedObservations.grow(truncatedObservationCardinalityNext, requested);
    }

    function _beforeSwap(uint32 time, int24 tick, uint128 activeLiquidity) internal override {
        _record(time, tick, activeLiquidity);
    }

    function _beforeLiquidityChange(
        uint32 time,
        int24 tick,
        uint128 activeLiquidity,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta
    ) internal override {
        if (liquidityDelta == 0 || tick < tickLower || tick >= tickUpper) {
            return;
        }
        _record(time, tick, activeLiquidity);
    }

    function _record(uint32 time, int24 spotTick, uint128 activeLiquidity) private {
        if (block.number == truncatedLastBlock) return;

        (truncatedObservationIndex, truncatedObservationCardinality) = _truncatedObservations.write(
            truncatedObservationIndex,
            time,
            truncatedTick,
            activeLiquidity,
            truncatedObservationCardinality,
            truncatedObservationCardinalityNext
        );

        truncatedTick =
            TruncatedOracle.nextTick(truncatedTick, spotTick, maxAbsTickMove, quoteIsToken0);
        truncatedLastBlock = uint64(block.number);
    }
}
