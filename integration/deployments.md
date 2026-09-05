# Deployments

## Robinhood Chain mainnet (chain ID 4663)

Canonical replacement deployment of 2026-08-30. RPC:
`https://rpc.mainnet.chain.robinhood.com/`

| Contract | Address |
| --- | --- |
| AbyssFactory | `0xe7feF2BC860B25bbdEB6F6AB96d88bAAa77ddad7` |
| AbyssRouter (V1) | `0xF7818c69e31bf98eFF96C721B557Bb519659CD27` |
| AbyssRouterV2 (native ETH boundary) | `0xF2a3Afb36768950eb2c7F04583328C09AEC0C366` |
| AbyssQuoter | `0xF1ff7c78605939df2d705F3E12Ac9CEB69Bcfe76` |
| AbyssPositionManager | `0x1b2176d4D2C7bd36227D92Ed84F1A3aE30B635bF` |
| AbyssPositionLocker | `0xa0d4fA31740FA0d8fc6b5b4173Da17864Eb6e888` |
| FeeVault | `0x19b04F2E86fFDf26510ACf25344c406240214d5F` |
| AbyssFeeRouter | `0x2c3B1b6fe0EDa8e10C0445567b47e66E825B34cd` |
| AbyssBuybackBurner | `0xF6C7159e967f28C65d9Fb5b919567E04540cD2FF` |
| ABYSS token | `0x15f3385625D7e364C5a6216FBbceadf10fa90e7d` |
| Canonical WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |
| Chainlink ETH/USD feed | `0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9` |

`AbyssPoolFeeLens` (batch protocol-fee inspection/claim adapter) and
`AbyssBatchQuoter` (batch quote adapter) are published in `src/periphery/` but
have no recorded canonical deployment address at publication time. Treat any
instance as untrusted until its address, factory binding, and code are
verified against this source.

## Fee tiers and oracle configurations

Enabled fee tiers (fee pips, tick spacing): `(500, 10)`, `(3000, 60)`,
`(10000, 200)`, `(20000, 400)`, `(50000, 1000)`, `(100000, 2000)`,
`(150000, 3000)`.

Robinhood mainnet truncated-oracle menu (maxAbsTickMove, cardinality):
P1 `(1, 4096)`, P2 `(6, 4096)`, P3 `(17, 4096)`. The oracle config ID is
`keccak256(abi.encode(OracleConfig))`; identical tuples produce identical IDs
on any chain.

## Verifying a deployment

Before integrating against any address:

1. Confirm the chain ID (`eth_chainId` = `0x1227` / 4663).
2. Confirm non-empty code at the address.
3. For pools, resolve through the factory: `factory.isPool(pool)` must be
   `true`, and `factory.getPool(poolId)` must equal the address for the
   complete `PoolKey`.
4. For periphery, confirm the immutable factory binding matches the canonical
   factory above.
