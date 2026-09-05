# Deployments

Everything an integrator needs to bind to Abyss without probing the chain is
in this document. Values are recorded from the canonical deployment evidence;
verify once at integration time (chain ID + code presence), then pin them.

## Robinhood Chain mainnet

| Property | Value |
| --- | --- |
| Chain ID | `4663` (`0x1227`) |
| Public RPC | `https://rpc.mainnet.chain.robinhood.com/` |
| Explorer | `https://robinhoodchain.blockscout.com` |
| Native currency | ETH (18 decimals) |
| Block cadence | ~0.1 s (Arbitrum L2) |
| Finality policy | Use the provider's `finalized` block tag |
| Multicall3 | `0xcA11bde05977b3631167028862bE2a173976CA11` (standard CREATE2 address) |

## Canonical contracts (replacement deployment, 2026-08-30)

| Contract | Address | Notes |
| --- | --- | --- |
| AbyssFactory | `0xe7feF2BC860B25bbdEB6F6AB96d88bAAa77ddad7` | Pool registry and creation |
| AbyssRouter (V1) | `0xF7818c69e31bf98eFF96C721B557Bb519659CD27` | ERC-20 swaps, `MAX_HOPS = 4` |
| AbyssRouterV2 | `0xF2a3Afb36768950eb2c7F04583328C09AEC0C366` | Adds native ETH boundary, `MAX_HOPS = 4` |
| AbyssQuoter | `0xF1ff7c78605939df2d705F3E12Ac9CEB69Bcfe76` | Exact quotes, `MAX_HOPS = 4` |
| AbyssPositionManager | `0x1b2176d4D2C7bd36227D92Ed84F1A3aE30B635bF` | ERC-721 liquidity positions |
| AbyssPositionLocker | `0xa0d4fA31740FA0d8fc6b5b4173Da17864Eb6e888` | Time/permanent NFT custody |
| FeeVault | `0x19b04F2E86fFDf26510ACf25344c406240214d5F` | Immutable protocol-fee destination; owned by the fee router |
| AbyssFeeRouter | `0x2c3B1b6fe0EDa8e10C0445567b47e66E825B34cd` | ERC-1967 proxy; splits treasury WETH |
| AbyssBuybackBurner | `0xF6C7159e967f28C65d9Fb5b919567E04540cD2FF` | Protocol receiver; buys and burns ABYSS |
| ABYSS token | `0x15f3385625D7e364C5a6216FBbceadf10fa90e7d` | See token registry below |
| Canonical WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | Wrapped native, 18 decimals |
| Chainlink ETH/USD | `0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9` | 8-decimal answers |

`AbyssPoolFeeLens` (batch protocol-fee inspection/claim adapter) and
`AbyssBatchQuoter` (batch quote adapter) are published in `src/periphery/` but
have no recorded canonical deployment address at publication time. Treat any
instance as untrusted until its address, factory binding, and code are
verified against this source.

## Token registry

| Token | Address | Decimals | Notes |
| --- | --- | --- | --- |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | 18 | Canonical wrapped native; router V2 native boundary unwraps to it |
| ABYSS | `0x15f3385625D7e364C5a6216FBbceadf10fa90e7d` | 18 | Fixed supply 100,000,000,000 (1e11); name "Abyss" |

## Pool profiles

| Profile | Enum value | Swap fee token | Oracle |
| --- | --- | --- | --- |
| `STANDARD` | 0 | Input token | Canonical v3 observations |
| `STANDARD_ORACLE` | 1 | Input token | Canonical + truncated |
| `QUOTE` | 2 | Designated quote token, both directions | Canonical v3 observations |
| `QUOTE_ORACLE` | 3 | Designated quote token, both directions | Canonical + truncated |

## Fee tiers

All seven tiers are enabled on the canonical factory. Fee is in pips
(`1e6` = 100%):

| Fee (pips) | Fee (%) | Tick spacing |
| --- | --- | --- |
| 500 | 0.05% | 10 |
| 3,000 | 0.30% | 60 |
| 10,000 | 1.00% | 200 |
| 20,000 | 2.00% | 400 |
| 50,000 | 5.00% | 1,000 |
| 100,000 | 10.00% | 2,000 |
| 150,000 | 15.00% | 3,000 |

## Oracle configuration IDs

The oracle config ID is `keccak256(abi.encode(OracleConfig{maxAbsTickMove,
cardinality}))` — deterministic, identical on any chain for the same tuple.
Registered on the canonical factory:

| Profile tier | maxAbsTickMove | Cardinality | oracleConfigId |
| --- | --- | --- | --- |
| P1 (blue-chip) | 1 | 4096 | `0xeee1f80886a96fd4dced62af707ecd72df000f86f2cfbbf26c8412c85cf99a4c` |
| P2 (mid-cap, default) | 6 | 4096 | `0xed7437cf34651a2490f41af2f7d7b3e8070fb4dfd66508667d7e7f2ff6b93ea9` |
| P3 (volatile) | 17 | 4096 | `0xc0e9bed88d70a13fd3ab31451fefdd073b7266e838aee0ad1c236c8c9eff855d` |

Pools without the truncated oracle use `oracleConfigId = bytes32(0)`.

## Canonical ABYSS/WETH pool

The launch pool, created by the token-setup transaction:

| Property | Value |
| --- | --- |
| Pool address | `0xDec74a2AfABD34aA6f268c5161D2E9e210ca7185` |
| token0 | WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| token1 | ABYSS `0x15f3385625D7e364C5a6216FBbceadf10fa90e7d` |
| Profile | `QUOTE_ORACLE` (3) |
| Fee | 10,000 pips (1.00%) |
| Tick spacing | 200 |
| Quote token | WETH (`quoteIsToken0 = true`) — all swap fees accrue in WETH |
| oracleConfigId | P3 `0xc0e9bed88d70a13fd3ab31451fefdd073b7266e838aee0ad1c236c8c9eff855d` |
| Protocol fee denominator | 6 (⅙ of quote fees to protocol) |
| Position NFT | `#2`, held permanently by the position locker (`unlockTime = 0`) |
| Position range | ticks `[-887200, 251400]`, one-sided ABYSS inventory above the launch tick |
| Position account | `0xE008FfF3044769b6af85b6B7eF76b9e66DEc9742` |

## Treasury flow configuration

| Setting | Value |
| --- | --- |
| FeeVault owner | AbyssFeeRouter proxy |
| FeeRouter dev share | 2,000 bps (20%) |
| Dev receiver | `0x7cb44b8693b3C350A2BcD4b681aF85365aa27783` |
| Protocol receiver | AbyssBuybackBurner (80%) |
| Locked position #2 fee recipient | `0x7cb44b8693b3C350A2BcD4b681aF85365aa27783` (permissionless claim) |

## Verifying a deployment

Before integrating against any address:

1. Confirm the chain ID (`eth_chainId` = `0x1227` / 4663).
2. Confirm non-empty code at the address.
3. For pools, resolve through the factory: `factory.isPool(pool)` must be
   `true`, and `factory.getPool(poolId)` must equal the address for the
   complete `PoolKey`.
4. For periphery, confirm the immutable factory binding matches the canonical
   factory above.
