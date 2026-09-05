# Router V2 and native ETH

`AbyssRouterV2` preserves every Router V1 ERC-20 endpoint and adds four
native-boundary endpoints. Pools remain ERC-20/WETH-only; native ETH exists
inside the router only within a single transaction.

Robinhood mainnet: `0xF2a3Afb36768950eb2c7F04583328C09AEC0C366`, bound to the
canonical factory and canonical WETH.

## V1 endpoints (unchanged)

`exactInputSingle`, `exactOutputSingle`, and `exactInput` behave exactly as
documented in [Swapping](swapping.md), except they are `payable` and revert
with `EthValueForbidden` when `msg.value != 0`.

## Native in: ETH → token

```solidity
function exactInputSingleFromETH(
    PoolKey calldata key,
    address recipient,
    bool zeroForOne,
    uint256 amountIn,             // WETH amount to wrap and swap
    uint256 amountOutMinimum,
    uint160 sqrtPriceLimitX96,
    uint256 deadline
) external payable returns (uint256 amountOut);

function exactInputFromETH(ExactInputParams calldata params)
    external payable returns (uint256 amountOut);
```

Semantics:

- The first hop's input token must be the canonical WETH (`NotWethRoute`
  otherwise).
- The router wraps exactly `amountIn` into WETH; `msg.value` must be at least
  `amountIn`.
- Any `msg.value` surplus is refunded to `msg.sender` alone — never to
  `recipient` or a third party.
- The first hop must consume exactly `amountIn`; otherwise the route reverts
  (`SlippageExceeded`). Exact-input pools always consume the full input, so
  this is a consistency check, not a slippage source.

## Native out: token → ETH

```solidity
function exactInputSingleToETH(
    PoolKey calldata key,
    address recipient,
    bool zeroForOne,
    uint256 amountIn,
    uint256 amountOutMinimum,
    uint160 sqrtPriceLimitX96,
    uint256 deadline
) external payable returns (uint256 amountOut);

function exactInputToETH(ExactInputParams calldata params)
    external payable returns (uint256 amountOut);
```

Semantics:

- The final hop's output token must be the canonical WETH.
- The pool pays WETH to the router, which unwraps exactly the route output
  and sends native ETH to `recipient`.
- If the recipient rejects ETH, the entire transaction reverts
  (`EthTransferFailed`) — no partial fill, no stranded WETH.

## Native-safety invariants

- `receive()` accepts ETH only from the immutable WETH contract while an
  unwrap is in progress. Plain ETH sends revert (`EthReceiptForbidden`).
- Forced ETH (e.g. via `selfdestruct`) can enter the balance but is never
  accounted and cannot be withdrawn by anyone. Do not send ETH to the router
  outside the payable endpoints.
- The swap callback never moves native ETH.
- There is no sweep function. Tokens sent directly to the router are not
  recoverable.

## Choosing V1 vs V2

- Pure ERC-20 routes: either router; V2 adds only the `msg.value` rejection.
- User pays or receives native ETH: V2 native endpoints.
- Integrations already built on V1 do not need to migrate; both routers are
  immutable and remain valid periphery over the same pools.
