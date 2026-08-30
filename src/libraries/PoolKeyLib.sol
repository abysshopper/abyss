// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { PoolKey, PoolProfile } from "../types/AbyssTypes.sol";

library PoolKeyLib {
    error IdenticalTokens();
    error ZeroToken();
    error InvalidQuoteToken();
    error NonCanonicalPoolKey();

    function canonicalize(
        address tokenA,
        address tokenB,
        PoolProfile profile,
        uint24 fee,
        address quoteToken,
        bytes32 oracleConfigId
    ) internal pure returns (PoolKey memory key) {
        if (tokenA == tokenB) revert IdenticalTokens();
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroToken();
        (key.token0, key.token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        key.profile = profile;
        key.fee = fee;

        bool hasQuote = profile != PoolProfile.STANDARD;
        bool hasOracle =
            profile == PoolProfile.STANDARD_ORACLE || profile == PoolProfile.QUOTE_ORACLE;
        if (hasQuote) {
            if (quoteToken != key.token0 && quoteToken != key.token1) revert InvalidQuoteToken();
            key.quoteIsToken0 = quoteToken == key.token0;
        } else if (quoteToken != address(0)) {
            revert NonCanonicalPoolKey();
        }
        if (hasOracle) {
            if (oracleConfigId == bytes32(0)) revert NonCanonicalPoolKey();
            key.oracleConfigId = oracleConfigId;
        } else if (oracleConfigId != bytes32(0)) {
            revert NonCanonicalPoolKey();
        }
    }

    function validate(PoolKey memory key) internal pure {
        if (key.token0 == key.token1) revert IdenticalTokens();
        if (key.token0 == address(0) || key.token1 == address(0)) revert ZeroToken();
        if (key.token0 > key.token1) revert NonCanonicalPoolKey();

        bool hasQuote = key.profile != PoolProfile.STANDARD;
        bool hasOracle =
            key.profile == PoolProfile.STANDARD_ORACLE || key.profile == PoolProfile.QUOTE_ORACLE;
        if (!hasQuote && key.quoteIsToken0) revert NonCanonicalPoolKey();
        if (hasOracle == (key.oracleConfigId == bytes32(0))) revert NonCanonicalPoolKey();
    }

    function id(PoolKey memory key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }
}
