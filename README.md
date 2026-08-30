![Abyss header](assets/abyss-header.png)

# Abyss

Abyss is a permissionless concentrated-liquidity DEX built for token launches. It keeps the familiar Uniswap v3 curve and adds fee and oracle modes designed around quote-token markets.

## Features

- **Concentrated liquidity.** LPs choose price ranges instead of spreading liquidity across the entire curve.
- **Quote-token fees.** Quote pools charge swap fees in the designated quote asset in both trade directions.
- **Four immutable pool profiles.** Pools select standard or quote-token fees, with either canonical observations alone or canonical plus truncated observations.
- **Truncated oracle observations.** Oracle-enabled pools maintain a parallel observation ring that limits how far the recorded tick can move at each eligible update.
- **Permissionless lifecycle.** Pool creation, initialization, liquidity management, and trading do not require an allowlist.
- **Core-enforced accounting.** Fee collection, settlement checks, and required oracle writes live in the pool rather than depending on a preferred router.
- **Complete trading periphery.** The source includes routing, quoting, NFT liquidity positions, position locking, fee custody and routing, buyback-and-burn, and the ABYSS token contracts.

## Audits

Abyss has completed three adversarial audit rounds with **Kimi K3**:

| Date | Scope | Result |
| --- | --- | --- |
| 2026-08-19 | Full Abyss source, modified v3 port, quote-fee math, deployment contracts, and a live Sepolia deployment | Findings were remediated and rechecked; the final remediated suite passed 140/140 tests |
| 2026-08-20 | Pinned pool and periphery source, differential fuzzing, invariants, and live Sepolia exploitation | No critical or high-severity vulnerability found; 15/15 local attacks and 11 live adversarial checks resisted |
| 2026-08-28 | Pool core, quote engine, settlement, oracle behavior, periphery changes, and the canonical launch path | No critical, high, or medium vulnerability found; all 8 proof-of-concept attack vectors resisted |

These were machine-conducted reviews of specific source snapshots. They are evidence, not a guarantee that the contracts are free of defects. The full audit artifacts are maintained separately from this source-only repository.

## Source

This repository contains the 63 Solidity contracts that make up Abyss, together with file-level provenance and the applicable license notices. The contracts are published for inspection.

Build dependencies, tests, deployment scripts, addresses, operational configuration, broadcasts, and private project history are deliberately excluded. This repository is therefore not a build or deployment package.

## License and provenance

Abyss includes source derived from Uniswap v3 and imports pinned Solady components. See:

- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Derivative source manifest](provenance/derivative-manifest.json)
- [License texts](licenses/)

The header artwork comes from the Abyss UI project.