// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;
// Derived in part from Uniswap V3 Periphery SwapRouter.sol; modified by the Abyss project
// on 2026-08-17, 2026-08-18, and 2026-08-22 for authenticated Abyss pool keys,
// callback settlement, deadlines, slippage, and bounded exact-input multihop routing.

import { IAbyssFactory } from "../interfaces/IAbyssFactory.sol";
import { IAbyssPool } from "../interfaces/IAbyssPool.sol";
import { IAbyssSwapCallback } from "../interfaces/IAbyssCallbacks.sol";
import { PoolKeyLib } from "../libraries/PoolKeyLib.sol";
import { PoolKey } from "../types/AbyssTypes.sol";
import { ExactInputHop, ExactInputParams } from "../types/AbyssPeripheryTypes.sol";

contract AbyssRouter is IAbyssSwapCallback {
    error DeadlineExpired();
    error InvalidPool();
    error InvalidAmount();
    error SlippageExceeded();
    error TokenTransferFailed();
    error EmptyRoute();
    error TooManyHops();
    error DisconnectedRoute();
    error RepeatedPool();
    error Reentrancy();

    uint256 public constant MAX_HOPS = 4;

    struct SwapCallbackData {
        PoolKey key;
        address pool;
        address payer;
    }

    IAbyssFactory public immutable factory;
    bool private entered;

    constructor(IAbyssFactory factory_) {
        factory = factory_;
    }

    function exactInputSingle(
        PoolKey calldata key,
        address recipient,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        _enter();
        _checkAmountAndDeadline(amountIn, deadline);
        (int256 amount0, int256 amount1) =
            _swap(key, recipient, zeroForOne, int256(amountIn), sqrtPriceLimitX96, msg.sender);
        amountOut = _negativeMagnitude(zeroForOne ? amount1 : amount0);
        if (amountOut < amountOutMinimum) revert SlippageExceeded();
        entered = false;
    }

    function exactOutputSingle(
        PoolKey calldata key,
        address recipient,
        bool zeroForOne,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    ) external returns (uint256 amountIn) {
        _enter();
        _checkAmountAndDeadline(amountOut, deadline);
        (int256 amount0, int256 amount1) =
            _swap(key, recipient, zeroForOne, -int256(amountOut), sqrtPriceLimitX96, msg.sender);
        uint256 delivered = _negativeMagnitude(zeroForOne ? amount1 : amount0);
        if (delivered != amountOut) revert SlippageExceeded();
        amountIn = uint256(zeroForOne ? amount0 : amount1);
        if (amountIn > amountInMaximum) revert SlippageExceeded();
        entered = false;
    }

    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut) {
        _enter();
        _checkAmountAndDeadline(params.amountIn, params.deadline);
        uint256 length = params.path.length;
        if (length == 0) revert EmptyRoute();
        if (length > MAX_HOPS) revert TooManyHops();

        uint256 amountIn = params.amountIn;
        address payer = msg.sender;
        address expectedInput;
        bytes32[] memory poolIds = new bytes32[](length);
        for (uint256 i; i < length; ++i) {
            ExactInputHop calldata hop = params.path[i];
            bool zeroForOne = _direction(hop.key, hop.tokenIn);
            if (i != 0 && hop.tokenIn != expectedInput) revert DisconnectedRoute();

            bytes32 poolId = PoolKeyLib.id(hop.key);
            for (uint256 j; j < i; ++j) {
                if (poolIds[j] == poolId) revert RepeatedPool();
            }
            poolIds[i] = poolId;
            expectedInput = zeroForOne ? hop.key.token1 : hop.key.token0;
            address recipient = i + 1 == length ? params.recipient : address(this);
            (int256 amount0, int256 amount1) = _swap(
                hop.key, recipient, zeroForOne, int256(amountIn), hop.sqrtPriceLimitX96, payer
            );
            amountIn = _negativeMagnitude(zeroForOne ? amount1 : amount0);
            payer = address(this);
        }
        amountOut = amountIn;
        if (amountOut < params.amountOutMinimum) revert SlippageExceeded();
        entered = false;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external
    {
        if (!entered) revert InvalidPool();
        SwapCallbackData memory callback = abi.decode(data, (SwapCallbackData));
        address resolvedPool = _resolvePool(callback.key);
        if (msg.sender != callback.pool || msg.sender != resolvedPool) revert InvalidPool();
        if (amount0Delta > 0) {
            _pay(callback.key.token0, callback.payer, msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            _pay(callback.key.token1, callback.payer, msg.sender, uint256(amount1Delta));
        }
    }

    function _swap(
        PoolKey calldata key,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        address payer
    ) private returns (int256 amount0, int256 amount1) {
        address pool = _resolvePool(key);
        bytes memory callbackData =
            abi.encode(SwapCallbackData({ key: key, pool: pool, payer: payer }));
        return IAbyssPool(pool)
            .swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, callbackData);
    }

    function _resolvePool(PoolKey memory key) private view returns (address pool) {
        PoolKeyLib.validate(key);
        bytes32 poolId = PoolKeyLib.id(key);
        pool = factory.getPool(poolId);
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

    function _checkAmountAndDeadline(uint256 amount, uint256 deadline) private view {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (amount == 0 || amount > uint256(type(int256).max)) revert InvalidAmount();
    }

    function _enter() private {
        if (entered) revert Reentrancy();
        entered = true;
    }

    function _pay(address token, address payer, address recipient, uint256 amount) private {
        bytes memory callData = payer == address(this)
            ? abi.encodeWithSelector(
                bytes4(keccak256("transfer(address,uint256)")), recipient, amount
            )
            : abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint256)")), payer, recipient, amount
            );
        (bool success, bytes memory result) = token.call(callData);
        if (
            !success || (result.length != 0 && result.length != 32)
                || (result.length == 32 && !abi.decode(result, (bool)))
        ) revert TokenTransferFailed();
    }

    function _negativeMagnitude(int256 value) private pure returns (uint256) {
        if (value >= 0) revert InvalidAmount();
        return uint256(-(value + 1)) + 1;
    }
}
