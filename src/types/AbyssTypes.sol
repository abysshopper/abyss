// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

enum PoolProfile {
    STANDARD,
    STANDARD_ORACLE,
    QUOTE,
    QUOTE_ORACLE
}

/// @notice Complete identity for an Abyss pool.
/// @dev Tokens are address-sorted. Unused quote and oracle fields must use their zero encoding.
struct PoolKey {
    address token0;
    address token1;
    PoolProfile profile;
    uint24 fee;
    bool quoteIsToken0;
    bytes32 oracleConfigId;
}

/// @notice Immutable truncated-observation configuration.
/// @param maxAbsTickMove Maximum absolute tick movement committed per eligible block.
/// @param cardinality Maximum number of truncated observations retained by the ring.
struct OracleConfig {
    uint24 maxAbsTickMove;
    uint16 cardinality;
}
