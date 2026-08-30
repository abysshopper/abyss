// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import { IAbyssFactory } from "./IAbyssFactory.sol";
import { IAbyssPool } from "./IAbyssPool.sol";
import { PoolKey } from "../types/AbyssTypes.sol";

interface IAbyssPositionManager {
    function factory() external view returns (IAbyssFactory);
    function nextTokenId() external view returns (uint256);

    function positions(uint256 tokenId)
        external
        view
        returns (address account, address pool, int24 tickLower, int24 tickUpper, uint128 liquidity);

    function accountFor(uint256 tokenId, address pool) external view returns (address account);

    function mint(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0Maximum,
        uint256 amount1Maximum,
        uint256 deadline
    ) external returns (uint256 tokenId, uint256 amount0, uint256 amount1);

    function createAndInitializePoolIfNecessary(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        uint160 existingPriceMinimumX96,
        uint160 existingPriceMaximumX96
    ) external returns (address pool, bool created);

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    function increaseLiquidity(
        uint256 tokenId,
        uint128 amount,
        uint256 amount0Maximum,
        uint256 amount1Maximum
    ) external returns (uint256 amount0, uint256 amount1);

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 amount,
        uint256 amount0Minimum,
        uint256 amount1Minimum,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);

    function collect(
        uint256 tokenId,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    function burnPosition(uint256 tokenId) external;
}

interface IAbyssPositionManagerSettlement {
    function settleMint(
        address account,
        IAbyssPool pool,
        address payer,
        uint256 amount0Owed,
        uint256 amount1Owed
    ) external;
}

interface IAbyssPositionAccount {
    function manager() external view returns (address);
    function pool() external view returns (IAbyssPool);

    function mintPosition(address payer, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1);

    function burnPosition(int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1);

    function pokePosition(int24 tickLower, int24 tickUpper) external;

    function collectPosition(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}
