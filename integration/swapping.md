# Swapping

Swaps execute against pools directly or through the canonical routers. The
routers authenticate complete `PoolKey`s against the factory, enforce
deadlines and slippage, and settle callbacks. Pool accounting is identical
either way; the router is convenience, not a security boundary.

## Quoting

Quote through `AbyssQuoter` — never approximate quote-profile fee math
locally for executable values.

```solidity
// Single pool
function quote(
    address pool,
    bool zeroForOne,
    int256 amountSpecified,       // > 0 exact input, < 0 exact output
    uint160 sqrtPriceLimitX96
) external returns (int256 amount0, int256 amount1);

// Bounded multihop, exact input only
function quoteExactInput(
    ExactInputHop[] memory path,  // 1..4 hops, connected, no repeated pool
    uint256 amountIn
) external returns (uint256 amountOut);
```

Quotes are state reads at one block. They are not execution guarantees;
always pair them with `amountOutMinimum` / `amountInMaximum` and a deadline.

`AbyssBatchQuoter.quoteExactInputs(requests)` evaluates up to 64 independent
exact-input requests (256 total hops) in one call and isolates per-request
reverts, returning `(success, amountOut, errorSelector)` per request. Use it
for route comparison; use the exact quoter result for the executable slippage
floor.

## Router V1 (`AbyssRouter`)

### Single pool, exact input

```solidity
function exactInputSingle(
    PoolKey calldata key,
    address recipient,
    bool zeroForOne,              // token0 -> token1 when true
    uint256 amountIn,
    uint256 amountOutMinimum,
    uint160 sqrtPriceLimitX96,    // 0 = no limit beyond pool bounds
    uint256 deadline
) external returns (uint256 amountOut);
```

### Single pool, exact output

```solidity
function exactOutputSingle(
    PoolKey calldata key,
    address recipient,
    bool zeroForOne,
    uint256 amountOut,
    uint256 amountInMaximum,
    uint160 sqrtPriceLimitX96,
    uint256 deadline
) external returns (uint256 amountIn);
```

### Multihop, exact input

```solidity
struct ExactInputHop {
    PoolKey key;
    address tokenIn;              // must equal the previous hop's output token
    uint160 sqrtPriceLimitX96;
}

struct ExactInputParams {
    ExactInputHop[] path;         // 1..4 hops
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint256 deadline;
}

function exactInput(ExactInputParams calldata params)
    external returns (uint256 amountOut);
```

Route validation: path must be connected, must not repeat a pool, and every
key must resolve to a canonical factory pool. Intermediate outputs pass
through the router within the transaction; the final hop pays `recipient`
directly. Any failure reverts the whole route atomically.

There is no multihop exact-output method in V1.

### Caller requirements

- Approve the router for the input token (`transferFrom` is used for the
  first hop).
- `amountIn`/`amountOut` must be `> 0` and fit `int256`.
- `deadline` is compared against `block.timestamp`; expired transactions
  revert.

## Worked flow (exact input, one hop)

1. Discover the pool and complete key from indexed `AbyssPoolCreated` events.
2. Pin a block; call `AbyssQuoter.quote(pool, zeroForOne, amountIn, limit)`.
3. Compute `amountOutMinimum` from the exact quote and the user's slippage
   policy.
4. Ensure input-token approval to the router.
5. Simulate `exactInputSingle` from the sender (`eth_call`); a revert here
   means the transaction would revert.
6. Submit with a fresh deadline.

## Failure modes to surface

| Revert | Meaning |
| --- | --- |
| `DeadlineExpired` | Deadline passed |
| `SlippageExceeded` | Output below minimum / input above maximum |
| `InvalidPool` | Key does not resolve to a canonical pool |
| `DisconnectedRoute` / `RepeatedPool` / `TooManyHops` / `EmptyRoute` | Invalid path |
| `TokenTransferFailed` | Input token rejected the settlement transfer |
| `InvalidAmount` | Zero or overflowing amount |

Unsupported tokens: fee-on-transfer, rebasing, and non-standard-return
ERC-20s can break settlement assumptions. Do not route them.
