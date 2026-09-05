// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;
// Derived in part from Uniswap V3 Periphery SwapRouter.sol; modified by the Abyss project
// on 2026-09-02 for authenticated Abyss pool keys, callback settlement, deadlines, slippage,
// bounded exact-input multihop routing, and a transaction-scoped native ETH boundary.

import { IAbyssFactory } from "../interfaces/IAbyssFactory.sol";
import { IAbyssPool } from "../interfaces/IAbyssPool.sol";
import { IAbyssSwapCallback } from "../interfaces/IAbyssCallbacks.sol";
import { PoolKeyLib } from "../libraries/PoolKeyLib.sol";
import { PoolKey } from "../types/AbyssTypes.sol";
import { ExactInputHop, ExactInputParams } from "../types/AbyssPeripheryTypes.sol";

/// @dev Minimal WETH9 surface exercised at the native boundary: `deposit` mints wrapped
///      tokens from attached native value and `withdraw` burns them, paying the caller ETH.
interface IWeth {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

/// @notice Authenticated Abyss swap router with a transaction-scoped native ETH boundary.
/// @dev Preserves the V1 ERC-20 endpoints and adds four native-boundary endpoints. Pools
///      remain WETH-only; native value exists only inside a single transaction. From-ETH
///      routes wrap exactly the required input and refund any explicit surplus to
///      `msg.sender` alone. To-ETH routes direct the final hop's WETH to this contract,
///      unwrap exactly the route output, and send the ETH to the requested recipient. Native
///      value is accepted only from the immutable WETH contract during `withdraw`; forced or
///      preexisting ETH is never accounted and cannot be withdrawn by anyone.
contract AbyssRouterV2 is IAbyssSwapCallback {
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
    error InvalidConfiguration();
    error EthValueForbidden();
    error NotWethRoute();
    error WethDepositFailed();
    error WethWithdrawFailed();
    error EthTransferFailed();
    error EthReceiptForbidden();

    uint256 public constant MAX_HOPS = 4;

    struct SwapCallbackData {
        PoolKey key;
        address pool;
        address payer;
    }

    IAbyssFactory public immutable factory;
    IWeth public immutable weth;
    bool private entered;
    bool private unwrapping;

    constructor(IAbyssFactory factory_, IWeth weth_) {
        if (
            address(factory_) == address(0) || address(factory_).code.length == 0
                || address(weth_) == address(0) || address(weth_).code.length == 0
        ) revert InvalidConfiguration();
        factory = factory_;
        weth = weth_;
    }

    /// @dev Accepts native value exclusively from the immutable WETH contract while a to-ETH
    ///      route is inside `withdraw`. Every other plain ETH transfer reverts, so forced or
    ///      misdirected ETH can never enter the unwrap accounting path.
    receive() external payable {
        if (msg.sender != address(weth) || !unwrapping) revert EthReceiptForbidden();
    }

    /// @notice V1 single-pool exact input over a complete pool key. Rejects native value.
    function exactInputSingle(
        PoolKey calldata key,
        address recipient,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    ) external payable returns (uint256 amountOut) {
        _rejectEthValue();
        _enter();
        _checkAmountAndDeadline(amountIn, deadline);
        (int256 amount0, int256 amount1) =
            _swap(key, recipient, zeroForOne, int256(amountIn), sqrtPriceLimitX96, msg.sender);
        amountOut = _negativeMagnitude(zeroForOne ? amount1 : amount0);
        if (amountOut < amountOutMinimum) revert SlippageExceeded();
        entered = false;
    }

    /// @notice V1 single-pool exact output over a complete pool key. Rejects native value.
    function exactOutputSingle(
        PoolKey calldata key,
        address recipient,
        bool zeroForOne,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    ) external payable returns (uint256 amountIn) {
        _rejectEthValue();
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

    /// @notice V1 bounded exact-input multihop over complete pool keys. Rejects native value.
    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        _rejectEthValue();
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

    /// @notice Single-pool exact input paid in native ETH. Wraps exactly `amountIn` into
    ///         WETH, settles the swap with this contract as payer, and refunds any
    ///         `msg.value` surplus to `msg.sender` alone.
    function exactInputSingleFromETH(
        PoolKey calldata key,
        address recipient,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    ) external payable returns (uint256 amountOut) {
        _enter();
        _checkAmountAndDeadline(amountIn, deadline);
        if (amountIn > msg.value) revert InvalidAmount();
        _requireWethInput(key, zeroForOne);
        _wrap(amountIn);
        (int256 amount0, int256 amount1) =
            _swap(key, recipient, zeroForOne, int256(amountIn), sqrtPriceLimitX96, address(this));
        if (uint256(zeroForOne ? amount0 : amount1) != amountIn) revert SlippageExceeded();
        amountOut = _negativeMagnitude(zeroForOne ? amount1 : amount0);
        if (amountOut < amountOutMinimum) revert SlippageExceeded();
        _refundSurplus(amountIn);
        entered = false;
    }

    /// @notice Bounded exact-input multihop paid in native ETH. The first hop must take WETH;
    ///         this contract wraps exactly `params.amountIn` and pays every hop from its own
    ///         transaction-scoped balance. Any `msg.value` surplus is refunded to
    ///         `msg.sender` alone.
    function exactInputFromETH(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        _enter();
        _checkAmountAndDeadline(params.amountIn, params.deadline);
        if (params.amountIn > msg.value) revert InvalidAmount();
        uint256 length = params.path.length;
        if (length == 0) revert EmptyRoute();
        if (length > MAX_HOPS) revert TooManyHops();
        if (params.path[0].tokenIn != address(weth)) revert NotWethRoute();
        _wrap(params.amountIn);

        uint256 amountIn = params.amountIn;
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
                hop.key,
                recipient,
                zeroForOne,
                int256(amountIn),
                hop.sqrtPriceLimitX96,
                address(this)
            );
            uint256 amountPaid = uint256(zeroForOne ? amount0 : amount1);
            if (i == 0 && amountPaid != params.amountIn) revert SlippageExceeded();
            amountIn = _negativeMagnitude(zeroForOne ? amount1 : amount0);
        }
        amountOut = amountIn;
        if (amountOut < params.amountOutMinimum) revert SlippageExceeded();
        _refundSurplus(params.amountIn);
        entered = false;
    }

    /// @notice Single-pool exact input paid in ERC-20 with native ETH out. The pool pays WETH
    ///         to this contract, which unwraps exactly the swap output and sends the ETH to
    ///         `recipient`. Rejects native value.
    function exactInputSingleToETH(
        PoolKey calldata key,
        address recipient,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    ) external payable returns (uint256 amountOut) {
        _rejectEthValue();
        _enter();
        _checkAmountAndDeadline(amountIn, deadline);
        _requireWethOutput(key, zeroForOne);
        (int256 amount0, int256 amount1) =
            _swap(key, address(this), zeroForOne, int256(amountIn), sqrtPriceLimitX96, msg.sender);
        amountOut = _negativeMagnitude(zeroForOne ? amount1 : amount0);
        if (amountOut < amountOutMinimum) revert SlippageExceeded();
        _unwrap(amountOut);
        _sendEth(recipient, amountOut);
        entered = false;
    }

    /// @notice Bounded exact-input multihop paid in ERC-20 with native ETH out. The final hop
    ///         must output WETH to this contract, which unwraps exactly the route output and
    ///         sends the ETH to `params.recipient`. Rejects native value.
    function exactInputToETH(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        _rejectEthValue();
        _enter();
        _checkAmountAndDeadline(params.amountIn, params.deadline);
        uint256 length = params.path.length;
        if (length == 0) revert EmptyRoute();
        if (length > MAX_HOPS) revert TooManyHops();
        {
            ExactInputHop calldata lastHop = params.path[length - 1];
            bool lastZeroForOne = _direction(lastHop.key, lastHop.tokenIn);
            if ((lastZeroForOne ? lastHop.key.token1 : lastHop.key.token0) != address(weth)) {
                revert NotWethRoute();
            }
        }

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
            (int256 amount0, int256 amount1) = _swap(
                hop.key, address(this), zeroForOne, int256(amountIn), hop.sqrtPriceLimitX96, payer
            );
            amountIn = _negativeMagnitude(zeroForOne ? amount1 : amount0);
            payer = address(this);
        }
        amountOut = amountIn;
        if (amountOut < params.amountOutMinimum) revert SlippageExceeded();
        _unwrap(amountOut);
        _sendEth(params.recipient, amountOut);
        entered = false;
    }

    /// @dev V1-equivalent authenticated settlement. The callback data is encoded by this
    ///      contract inside `_swap`, so the pool, complete key, and payer are all committed
    ///      before the pool calls back; factory resolution is repeated here before any
    ///      transfer. Only the exact positive deltas requested by the authenticated pool are
    ///      paid, only to that pool, and only while an entry point holds the reentrancy lock.
    ///      The callback never moves native ETH.
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

    function _rejectEthValue() private view {
        if (msg.value != 0) revert EthValueForbidden();
    }

    function _requireWethInput(PoolKey memory key, bool zeroForOne) private view {
        PoolKeyLib.validate(key);
        if ((zeroForOne ? key.token0 : key.token1) != address(weth)) revert NotWethRoute();
    }

    function _requireWethOutput(PoolKey memory key, bool zeroForOne) private view {
        PoolKeyLib.validate(key);
        if ((zeroForOne ? key.token1 : key.token0) != address(weth)) revert NotWethRoute();
    }

    function _wrap(uint256 amount) private {
        (bool success,) =
            address(weth).call{ value: amount }(abi.encodeWithSelector(IWeth.deposit.selector));
        if (!success) revert WethDepositFailed();
    }

    function _unwrap(uint256 amount) private {
        unwrapping = true;
        (bool success,) =
            address(weth).call(abi.encodeWithSelector(IWeth.withdraw.selector, amount));
        if (!success) revert WethWithdrawFailed();
        unwrapping = false;
    }

    function _refundSurplus(uint256 amountIn) private {
        uint256 surplus = msg.value - amountIn;
        if (surplus != 0) _sendEth(msg.sender, surplus);
    }

    function _sendEth(address recipient, uint256 amount) private {
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert EthTransferFailed();
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
