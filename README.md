![Abyss header](assets/abyss-header.png)

# Abyss

> **Experimental.** Abyss has undergone multiple machine-conducted adversarial audits by Kimi K3. These reviews do not guarantee the absence of flaws and are not a substitute for an independent human security audit.

This repository publishes a curated snapshot of the Solidity source for public inspection. It is not a working repository, build package, deployed-bytecode verification package, or operational release.

## Review status

- Kimi K3 performed multiple rounds of adversarial static analysis and Foundry proof-of-concept testing against recorded Abyss source snapshots.
- The latest recorded round reported no critical, high, or medium vulnerability and no successful exploit across its eight proof-of-concept vectors.
- Audit conclusions apply only to each report's stated scope and reviewed revision; later source changes are not implicitly covered.
- The audit artifacts are maintained separately and are intentionally not included in this source-only disclosure.

## Contents

This disclosure contains exactly **71 regular files**:

- **63 Solidity source files** under [`src/`](src/), copied unchanged from the project source tree;
- **1 derivative provenance ledger** at [`provenance/derivative-manifest.json`](provenance/derivative-manifest.json);
- **4 complete license texts** in [`licenses/`](licenses/): [GPL-2.0-or-later](licenses/GPL-2.0-or-later.txt), [Uniswap v3 BUSL-1.1](licenses/Uniswap-v3-BUSL-1.1.txt), [Uniswap v3 MIT](licenses/Uniswap-v3-MIT.txt), and [Solady MIT](licenses/Solady-MIT.txt);
- **1 project-owned branding image** at [`assets/abyss-header.png`](assets/abyss-header.png); and
- this README plus the curated [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Intentionally omitted are dependency and library source (including Solady), build configuration, package and lock files, tests, scripts, deployment or broadcast material, operational addresses and configuration, artifacts, caches, audits, analyses, threat models, private specifications and documentation, CI material, Git metadata or history, and secrets.

## Layout for inspection

- [`src/core/`](src/core/), including [`src/core/v3/`](src/core/v3/), contains pool and concentrated-liquidity source.
- [`src/factory/`](src/factory/), [`src/interfaces/`](src/interfaces/), [`src/types/`](src/types/), and [`src/libraries/`](src/libraries/) contain supporting project source.
- [`src/periphery/`](src/periphery/) and [`src/governance/`](src/governance/) contain the included peripheral and ownership-related source.
- [`provenance/`](provenance/) records derivative identities; [`licenses/`](licenses/) holds the included license texts; and [`assets/`](assets/) holds the disclosure header.

Dependencies and build configuration are intentionally absent. The included imports therefore do not make this tree buildable, runnable, deployable, or a representation of deployed bytecode.

## Attribution and provenance

Read the curated [third-party notices](THIRD_PARTY_NOTICES.md), the [derivative ledger](provenance/derivative-manifest.json), and the applicable [license texts](licenses/) together with each Solidity file's SPDX header and notices.

The header image was copied unchanged from the Abyss UI project's `public/abyss-social.png` under project-owner authorization. It is project-owned branding, not third-party material, and is not swept into or granted by any Solidity license.