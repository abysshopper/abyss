# Third-Party and Derived Source Notices

This notice is limited to third-party and derived-source facts relevant to the files in this disclosure. It is factual attribution only. Individual SPDX headers, file notices, and the applicable license texts control.

## Uniswap v3 core derivatives

The derivative ledger records **31 ports of Uniswap v3 core** from commit [`e3589b192d0be27e100cd0daaf6c97204fdb1899`](provenance/derivative-manifest.json), with factual attribution to Uniswap Labs and contributors. It also records two core-derived, split/adapted contracts: [`src/core/AbyssPoolBase.sol`](src/core/AbyssPoolBase.sol) and [`src/core/AbyssQuotePoolBase.sol`](src/core/AbyssQuotePoolBase.sol). Together these are the ledger's 33 records originating from the pinned Uniswap v3 core revision.

For those core origins, the ledger preserves upstream blob identities, local digests, upstream and local SPDX identifiers, modification dates, and change categories. The pinned v3-core root BUSL-1.1 instrument records a 2023-04-01 change date and GPL-2.0-or-later change license. That change-license history is included as factual provenance; it does not override an individual file's SPDX header or applicable license text.

[`src/core/v3/libraries/FullMath.sol`](src/core/v3/libraries/FullMath.sol) retains its credit to Remco Bloemen under the MIT license for the multiplication-and-division method.

## Uniswap v3 periphery derivatives

The ledger records three conservatively classified adaptations from Uniswap v3 periphery commit [`80f26c86c57b8a5e4b913f42844d4c8bd274d058`](provenance/derivative-manifest.json): [`src/periphery/AbyssRouter.sol`](src/periphery/AbyssRouter.sol), [`src/periphery/AbyssQuoter.sol`](src/periphery/AbyssQuoter.sol), and [`src/periphery/AbyssPositionManager.sol`](src/periphery/AbyssPositionManager.sol). They correspond respectively to the pinned upstream `SwapRouter.sol`, `Quoter.sol`, and `NonfungiblePositionManager.sol` identities recorded in the ledger. The source provenance record identifies the selected periphery files as GPL-2.0-or-later-headered; each staged file's SPDX header and notices remain controlling.

A fourth record, added 2026-09-05, classifies [`src/periphery/AbyssRouterV2.sol`](src/periphery/AbyssRouterV2.sol) as derived in part from the same pinned upstream `SwapRouter.sol` identity, per its file notice. It is conservatively recorded at the ledger's periphery commit because the upstream blob identity has not been separately verified; the file header and the applicable license texts control. [`src/periphery/AbyssPoolFeeLens.sol`](src/periphery/AbyssPoolFeeLens.sol) and [`src/periphery/AbyssBatchQuoter.sol`](src/periphery/AbyssBatchQuoter.sol) are original Abyss project sources with no third-party derivation and therefore have no ledger records.

## Solady imports

Included source imports Solady's `ERC721`, `ERC20`, `Ownable`, `UUPSUpgradeable`, `Initializable`, `SafeTransferLib`, and `ReentrancyGuard` components from commit [`acd959aa4bd04720d640bf4e6a5c71037510cc4b`](provenance/derivative-manifest.json). Solady is MIT-licensed and attributed to Solady contributors. Its source is intentionally absent from this disclosure, so the imports are unresolved here and this tree is not a buildable package.

At that pinned lineage, Solady source retains “Modified from Solmate” and “Modified from OpenZeppelin” notices and links where present. Those upstream sources are not included here; this statement records lineage and does not add a license grant or attribution beyond the controlling materials.

## Records and license texts

The [`provenance/derivative-manifest.json`](provenance/derivative-manifest.json) ledger is the file-level provenance record for the 37 listed derivatives. It records origin identities and modifications; it is not deployed-bytecode verification, a completeness assertion, an audit, or a legal conclusion.

Complete included license texts are available at:

- [GPL-2.0-or-later](licenses/GPL-2.0-or-later.txt)
- [Uniswap v3 BUSL-1.1](licenses/Uniswap-v3-BUSL-1.1.txt)
- [Uniswap v3 MIT](licenses/Uniswap-v3-MIT.txt)
- [Solady MIT](licenses/Solady-MIT.txt)

Nothing in this disclosure implies endorsement by Uniswap, Solady, Solmate, OpenZeppelin, or their contributors. This notice is not legal advice, a license determination, an audit, or a security assessment.