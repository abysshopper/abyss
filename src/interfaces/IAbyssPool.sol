// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { PoolProfile } from "../types/AbyssTypes.sol";

interface IAbyssPool {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function tickSpacing() external view returns (int24);
    function quoteIsToken0() external view returns (bool);
    function protocolFees() external view returns (uint128 token0, uint128 token1);
    function initialize(uint160 sqrtPriceX96) external;

    function mint(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    function burn(int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1);

    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data)
        external;

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        );

    function observeTruncated(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        );

    function setProtocolFeeDenominator(uint8 denominator) external;
    function claimProtocolFees() external returns (uint128 amount0, uint128 amount1);
}
