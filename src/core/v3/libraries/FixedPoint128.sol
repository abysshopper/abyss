// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

// Modified by the Abyss project on 2026-08-17 for Solidity 0.8.26 and Abyss integration.

/// @title FixedPoint128
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
library FixedPoint128 {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
}
