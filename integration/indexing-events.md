# Indexing events

Abyss emits canonical Uniswap v3-compatible pool events plus Abyss-specific
metadata and treasury events. This document is the integration contract for
indexers.

## Pool discovery

Subscribe to the factory. Two events are emitted per pool creation; they are
complementary, not duplicates to reconcile by replacement:

```solidity
// v3-indexer compatibility; lacks profile, quote orientation, oracle config.
event PoolCreated(
    address indexed token0,
    address indexed token1,
    uint24 indexed fee,
    int24 tickSpacing,
    address pool
);
// topic0: 0x783cca1c0412dd0d695e784568c96da2e9c22ff989357a2e8b1d9b2b4e6b7118

// Authoritative Abyss topology. Use this for the complete PoolKey.
event AbyssPoolCreated(
    address indexed token0,
    address indexed token1,
    uint24 indexed fee,
    PoolProfile profile,
    bool quoteIsToken0,
    bytes32 oracleConfigId,
    address pool
);
// topic0: 0x50d43e7ef0c97a9b965bfd029f8421ae23eefcfee0d9ff2854d5071a070c0ed6
```

Rules:

- Build pool topology from `AbyssPoolCreated` only. `PoolCreated` exists for
  v3-compatible indexers and must not be used as a topology source because it
  omits profile, quote orientation, and oracle configuration.
- Key pools by `(chainId, pool)` and store the complete key.
- Start indexing at the factory's deployment block, never block zero.

## Pool activity

Pools emit the canonical v3 event set:

| Event | Use |
| --- | --- |
| `Initialize` | First price; pool becomes active |
| `Mint` / `Burn` | Liquidity deltas per owner/tick range |
| `Swap` | Signed `amount0`/`amount1` deltas, post-swap `sqrtPriceX96`, tick, liquidity |
| `Collect` | LP/user fee withdrawal (realized LP fees) |
| `CollectProtocol` | Protocol-fee withdrawal to the FeeVault (realized protocol revenue) |
| `Flash` | Flash loan amounts and fees |
| `IncreaseObservationCardinalityNext` | Oracle ring growth |

Abyss adds:

```solidity
event ProtocolFeeDenominatorChanged(uint8 oldDenominator, uint8 newDenominator);
```

Track it per pool: it changes the protocol share of future fees. The factory
emits `DefaultProtocolFeeDenominatorChanged` for the default inherited by
later pools; apply events in canonical transaction/log order, including
same-block changes.

Claimed-fee metrics are realized claims only: pool `Collect` is LP/user
claimed; pool `CollectProtocol` is protocol claimed. Locker wrapper events,
ERC-20 `Transfer` events, and FeeVault treasury transfers are not additional
fee sources — do not double count them.

## Position ownership

`AbyssPositionManager` is ERC-721. Track `Transfer` mints, ownership changes,
and burns (`to == 0x0`) for current ownership. Ownership is discovery data;
re-read `ownerOf(tokenId)` before any action that depends on it.

`AbyssPositionLocker` custody events:

```solidity
event PositionLocked(
    uint256 indexed tokenId,
    address indexed owner,
    address indexed feeRecipient,
    address claimAuthority,
    uint64 unlockTime,       // 0 = permanent
    bool permissionlessClaim
);
// topic0: 0x5fca0142d04f6cb973a910766f358d92f22f5649e89d3ce5cf03fecaa44cd0e5

event FeesClaimed(uint256 indexed tokenId, address indexed recipient, uint128 amount0, uint128 amount1);
event ClaimConfigurationUpdated(uint256 indexed tokenId, address indexed claimAuthority, address indexed feeRecipient, bool permissionlessClaim);
event LockExtended(uint256 indexed tokenId, uint64 previousUnlockTime, uint64 newUnlockTime);
event LockOwnershipTransferred(uint256 indexed tokenId, address indexed previousOwner, address indexed newOwner);
event PositionWithdrawn(uint256 indexed tokenId, address indexed owner, address indexed recipient);
```

## Treasury events

- Pool `CollectProtocol(sender, feeVault, amount0, amount1)`: protocol fees
  moved from pool accounting into the immutable FeeVault.
- `FeeVault.TreasuryTransfer(token, recipient, amount)`: owner-initiated
  treasury movement out of the vault.
- `AbyssFeeRouter.Distributed(...)`: WETH split between developer and
  protocol receivers. `AbyssDistributed(...)`: in-kind ABYSS split.
- `AbyssPoolFeeLens.ProtocolFeesClaimed(pool, canonical, success, amount0,
  amount1, errorSelector)`: per-pool outcome of a batch claim. Reconcile
  against the pool's own `CollectProtocol`; a lens success event without the
  matching pool event is not revenue.

## Oracle observations

Oracle-enabled pools maintain both the canonical v3 observation ring and a
truncated ring that clamps per-update tick movement. Query canonical history
with `observe(secondsAgos)` and truncated history with
`observeTruncated(secondsAgos)`. Insufficient history reverts; indexers should
treat that as a typed failure, not missing data.

## Finality and reorgs

Robinhood Chain is an Arbitrum L2 with ~0.1 s blocks. Use the provider's
`finalized` block tag where available rather than a fixed confirmation depth.
Deduplicate on `(chainId, blockHash, txHash, logIndex)`. On reorg, roll back
by block hash and replay; never treat log index alone as stable across forks.
