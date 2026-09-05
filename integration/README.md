# Integrating with Abyss

This directory documents how external systems integrate with deployed Abyss
contracts: indexing pool and position events, quoting and executing swaps
through the routers, managing NFT liquidity positions, and understanding fee
flows.

| Document | Contents |
| --- | --- |
| [Deployments](deployments.md) | Canonical contract addresses and chain configuration |
| [Indexing events](indexing-events.md) | Event catalog, topics, discovery, and reorg handling |
| [Swapping](swapping.md) | Quoter and Router V1 exact-input/exact-output integration |
| [Router V2 and native ETH](router-v2.md) | Native-in/native-out routes and their invariants |
| [Positions and fees](positions-and-fees.md) | Position NFTs, the locker, protocol fees, and fee sweeping |

## Core concepts

### Complete pool keys

Every Abyss pool is identified by a complete `PoolKey`, never by token pair
alone:

```solidity
struct PoolKey {
    address token0;          // lower-sorted token address
    address token1;          // higher-sorted token address
    PoolProfile profile;     // STANDARD, STANDARD_ORACLE, QUOTE, QUOTE_ORACLE
    uint24 fee;              // fee in pips (1e6 = 100%)
    bool quoteIsToken0;      // which token is the quote token
    bytes32 oracleConfigId;  // truncated-oracle configuration, zero if unused
}
```

Parallel pools may share a token pair and differ in profile, fee, quote
orientation, or oracle configuration. Integrations must carry the complete key
through discovery, quoting, and execution.

### Pool profiles

| Profile | Swap fee token | Oracle |
| --- | --- | --- |
| `STANDARD` | Input token | Canonical v3 observations |
| `STANDARD_ORACLE` | Input token | Canonical + truncated observations |
| `QUOTE` | Designated quote token, both directions | Canonical v3 observations |
| `QUOTE_ORACLE` | Designated quote token, both directions | Canonical + truncated observations |

Quote-profile fee accounting is not a generic `(1 - fee)` multiplier; exact
integer rounding is profile-specific. Always quote through the deployed
quoter contracts rather than reimplementing fee math for executable values.

### Permissionless lifecycle

Pool creation, initialization, liquidity management, trading, and protocol-fee
claims are permissionless. There is no allowlist and no pause. The canonical
routers are convenience periphery, not a security boundary: pool-level
accounting is identical for direct callers.

## Safety rules for integrators

- Resolve pools through the factory (`getPool` / `isPool`); never trust a
  client-supplied pool address.
- Quote and simulate against a pinned block; include a deadline and slippage
  bound in every swap.
- Treat every ERC-20 as adversarial. Fee-on-transfer, rebasing, and
  non-standard-return tokens are not supported by the routers.
- Indexed data is discovery data. Re-read mutable state (ownership, prices,
  fee counters) from RPC before acting on it.
- Routers hold no user funds between transactions. There is no sweep or
  rescue function; tokens sent directly to a router are not recoverable.
