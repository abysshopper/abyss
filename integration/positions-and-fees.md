# Positions and fees

## Position NFTs (`AbyssPositionManager`)

Liquidity positions are ERC-721 NFTs backed one-to-one by deterministic,
immutable per-NFT custody accounts. Key surface:

```solidity
function positions(uint256 tokenId) external view
    returns (address account, address pool, int24 tickLower, int24 tickUpper, uint128 liquidity);

function mint(address pool, address recipient, int24 tickLower, int24 tickUpper,
    uint128 liquidity, uint256 amount0Maximum, uint256 amount1Maximum, uint256 deadline)
    external returns (uint256 tokenId, uint256 amount0, uint256 amount1);

function increaseLiquidity(uint256 tokenId, uint128 amount,
    uint256 amount0Maximum, uint256 amount1Maximum)
    external returns (uint256 amount0, uint256 amount1);

function decreaseLiquidity(uint256 tokenId, uint128 amount,
    uint256 amount0Minimum, uint256 amount1Minimum, uint256 deadline)
    external returns (uint256 amount0, uint256 amount1);

function collect(uint256 tokenId, address recipient,
    uint128 amount0Requested, uint128 amount1Requested)
    external returns (uint128 amount0, uint128 amount1);

function createAndInitializePoolIfNecessary(PoolKey calldata key,
    uint160 sqrtPriceX96, uint160 existingPriceMinimumX96, uint160 existingPriceMaximumX96)
    external returns (address pool, bool created);
```

Integrations should hydrate live position state (liquidity, fees owed, pool
price) from RPC rather than trusting indexed values for actions.

## Locked positions (`AbyssPositionLocker`)

Optional custody for time-locked or permanently locked position NFTs. A lock
record is set at transfer time:

```solidity
struct Lock {
    address owner;
    address claimAuthority;
    address feeRecipient;
    uint64 unlockTime;          // 0 = permanent; withdraw() always reverts
    bool permissionlessClaim;
}
```

- `claim(tokenId)` collects accrued LP fees to the lock's `feeRecipient`.
  When `permissionlessClaim` is true, anyone may trigger it; the destination
  never changes because of who calls.
- The lock owner may rotate `claimAuthority`/`feeRecipient` and extend (never
  shorten) a finite lock, even on permanent locks for the claim configuration.
- `withdraw` requires a finite, expired lock.

## Protocol fees

Each pool accrues its protocol share in `protocolFees()` counters
(`token0`/`token1` units). The factory's default denominator is inherited at
creation; per-pool changes emit `ProtocolFeeDenominatorChanged`.

```solidity
function claimProtocolFees() external returns (uint128 amount0, uint128 amount1);
```

- Permissionless; anyone may call it.
- Destination is fixed: the pool's immutable FeeVault. The caller cannot
  redirect proceeds.
- Transfers only the recorded counters — never LP principal or pool balances.
- In quote-profile pools, fees accrue only in the quote-token slot; the other
  counter stays zero.

## Batch inspection and claims (`AbyssPoolFeeLens`)

Peripheral adapter bound immutably to one factory. It never receives or
approves treasury tokens; pools pay the FeeVault directly.

```solidity
// One eth_call for up to 64 pools: canonical flag, read success,
// token0/token1, accrued protocol amounts, and revert selector per pool.
function inspect(address[] calldata pools) external view returns (PoolFees[] memory);

// One transaction for up to 64 pools: revalidates factory membership,
// isolates per-pool reverts, emits ProtocolFeesClaimed per input.
function claim(address[] calldata pools) external returns (ClaimResult[] memory);
```

Intended keeper flow: discover pools from indexed `AbyssPoolCreated` events,
batch-`inspect`, value the counters off-chain, estimate gas on the exact
`claim` calldata, and submit only when batch value clears the cost policy.
Duplicate inputs are safe but wasteful (later duplicates claim zero).

## Treasury path

```text
pool.protocolFees() ──claimProtocolFees()──▶ FeeVault ──FeeRouter.distribute()──▶ dev receiver (20%)
                                                                                └▶ protocol receiver (80%, e.g. BuybackBurner)
```

`AbyssFeeRouter.distribute()` is owner-only and moves the vault's entire WETH
balance. Non-WETH fee tokens must first be converted via owner-supplied
`swapToWeth` routes. None of this is automatic; keepers or operators must
trigger each step.
