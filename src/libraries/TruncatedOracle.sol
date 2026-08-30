// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

/// @notice Shared quote-orientation and tick-clamping transition for truncated oracle profiles.
library TruncatedOracle {
    function normalizeTick(int24 spotTick, bool quoteIsToken0) internal pure returns (int24) {
        return quoteIsToken0 ? -spotTick : spotTick;
    }

    function nextTick(int24 previousTick, int24 spotTick, int24 maxAbsTickMove, bool quoteIsToken0)
        internal
        pure
        returns (int24)
    {
        int256 delta = int256(normalizeTick(spotTick, quoteIsToken0)) - int256(previousTick);
        int256 cap = int256(maxAbsTickMove);
        if (delta > cap) delta = cap;
        else if (delta < -cap) delta = -cap;
        // The normalized target and previous tick are in TickMath's int24 range; clamping the
        // difference cannot move the result beyond the target.
        return int24(int256(previousTick) + delta);
    }
}
