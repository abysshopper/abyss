// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;
// Derived in part from Uniswap V3 Periphery Quoter.sol; modified by the Abyss project
// on 2026-08-17, 2026-08-18, 2026-08-19, and 2026-08-22 for execution-backed single-pool and
// bounded exact-input route quotes over complete Abyss pool identities.

import { IAbyssFactory } from "../interfaces/IAbyssFactory.sol";
import { IAbyssPool } from "../interfaces/IAbyssPool.sol";
import { IAbyssSwapCallback } from "../interfaces/IAbyssCallbacks.sol";
import { PoolKeyLib } from "../libraries/PoolKeyLib.sol";
import { PoolKey } from "../types/AbyssTypes.sol";
import { ExactInputHop } from "../types/AbyssPeripheryTypes.sol";

/// @notice Execution-backed quoter. Calls always revert at settlement, so pool/token state is unchanged.
contract AbyssQuoter is IAbyssSwapCallback {
    error InvalidPool();
    error InvalidAmount();
    error EmptyRoute();
    error TooManyHops();
    error DisconnectedRoute();
    error RepeatedPool();
    error QuoteResult(int256 amount0, int256 amount1);
    error UnexpectedQuoteFailure();

    uint256 public constant MAX_HOPS = 4;

    IAbyssFactory public immutable factory;
    address private activePool;

    constructor(IAbyssFactory factory_) {
        factory = factory_;
    }

    function quote(address pool, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96)
        external
        returns (int256 amount0, int256 amount1)
    {
        return _quote(pool, zeroForOne, amountSpecified, sqrtPriceLimitX96);
    }

    function quoteExactInput(ExactInputHop[] calldata path, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        uint256 length = path.length;
        if (length == 0) revert EmptyRoute();
        if (length > MAX_HOPS) revert TooManyHops();
        if (amountIn == 0 || amountIn > uint256(type(int256).max)) revert InvalidAmount();

        address expectedInput;
        bytes32[] memory poolIds = new bytes32[](length);
        for (uint256 i; i < length; ++i) {
            ExactInputHop calldata hop = path[i];
            bool zeroForOne = _direction(hop.key, hop.tokenIn);
            if (i != 0 && hop.tokenIn != expectedInput) revert DisconnectedRoute();
            bytes32 poolId = PoolKeyLib.id(hop.key);
            for (uint256 j; j < i; ++j) {
                if (poolIds[j] == poolId) revert RepeatedPool();
            }
            poolIds[i] = poolId;
            address pool = _resolvePool(hop.key);
            expectedInput = zeroForOne ? hop.key.token1 : hop.key.token0;
            (int256 amount0, int256 amount1) =
                _quote(pool, zeroForOne, int256(amountIn), hop.sqrtPriceLimitX96);
            amountIn = _negativeMagnitude(zeroForOne ? amount1 : amount0);
        }
        amountOut = amountIn;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata)
        external
        view
    {
        if (msg.sender != activePool || !factory.isPool(msg.sender)) revert InvalidPool();
        revert QuoteResult(amount0Delta, amount1Delta);
    }

    function _quote(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) private returns (int256 amount0, int256 amount1) {
        if (!factory.isPool(pool)) revert InvalidPool();
        address previousActivePool = activePool;
        activePool = pool;
        try IAbyssPool(pool)
            .swap(
                address(this), zeroForOne, amountSpecified, sqrtPriceLimitX96, bytes("")
            ) returns (
            int256, int256
        ) {
            revert UnexpectedQuoteFailure();
        } catch (bytes memory reason) {
            activePool = previousActivePool;
            if (reason.length != 68) _bubble(reason);
            bytes4 selector;
            assembly ("memory-safe") {
                selector := mload(add(reason, 0x20))
                amount0 := mload(add(reason, 0x24))
                amount1 := mload(add(reason, 0x44))
            }
            if (selector != QuoteResult.selector) _bubble(reason);
        }
    }

    function _resolvePool(PoolKey memory key) private view returns (address pool) {
        PoolKeyLib.validate(key);
        pool = factory.getPool(PoolKeyLib.id(key));
        if (pool == address(0) || !factory.isPool(pool)) revert InvalidPool();
    }

    function _direction(PoolKey memory key, address tokenIn)
        private
        pure
        returns (bool zeroForOne)
    {
        PoolKeyLib.validate(key);
        if (tokenIn == key.token0) return true;
        if (tokenIn == key.token1) return false;
        revert DisconnectedRoute();
    }

    function _negativeMagnitude(int256 value) private pure returns (uint256) {
        if (value >= 0) revert InvalidAmount();
        return uint256(-(value + 1)) + 1;
    }

    function _bubble(bytes memory reason) private pure {
        if (reason.length == 0) revert UnexpectedQuoteFailure();
        assembly ("memory-safe") {
            revert(add(reason, 0x20), mload(reason))
        }
    }
}
