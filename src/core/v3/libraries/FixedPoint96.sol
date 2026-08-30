// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

// Modified by the Abyss project on 2026-08-17 for Solidity 0.8.26 and Abyss integration.

/// @title FixedPoint96
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
/// @dev Used in SqrtPriceMath.sol
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}
