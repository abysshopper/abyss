// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { PoolKey } from "./AbyssTypes.sol";

/// @notice One directed exact-input route hop over a complete Abyss pool identity.
struct ExactInputHop {
    PoolKey key;
    address tokenIn;
    uint160 sqrtPriceLimitX96;
}

/// @notice Exact-input route parameters shared by the router and quoter.
struct ExactInputParams {
    ExactInputHop[] path;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint256 deadline;
}
