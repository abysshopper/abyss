# Zero-liquidity-safe market charts
This is a dependency-free, embeddable replacement chart for Abyss pools. It
does not change deployed pool contracts, DexScreener, or the live Abyss website.
This public repository contains source disclosures/integration material, not
the production website frontend. The site maintainer must explicitly replace
the embedded DexScreener iframe with this implementation and connect the
canonical event indexer. An overlay cannot remove the invalid 0-price candles
from inside a third-party iframe.
## Real failure reconstructed
USDG/WETH Abyss pool:
0xb39c61326bdba51586eac45f6bb418364fc65c92
(chain 4663). The final swap on November 4, 2026 at 01:11:02 UTC,
block 105505743, sold 299389.675986963248145871 USDG and paid
0.001952492291187482 WETH, finishing at tick 887271 with zero
active liquidity. The execution price was roughly $0.00001466 per
USDG at an illustrative WETH quote of $2247.91, *not* zero. The
embedded chart instead represented the terminal pool spot state as -100%.
Trigger transaction:
https://robinhoodchain.blockscout.com/tx/0x8f1f11c129a4b2f1ed0fd074a7b9bfba4df66caa254fca82e87b26639b6ab610
## Visible chart fix
- Identify pools from authoritative AbyssPoolCreated including full PoolKey.
- Index finalized Swap logs, joined with canonical timestamps and reorg keys.
- Decode signed event deltas and calculate executed quote/base price, adjusted
  for ERC-20 decimals, not the post-swap boundary sqrtPriceX96.
- Build 15-minute (configurable) OHLC candles from executions. Never synthesize
  empty intervals as zero-valued candles. Do not mistake a missing candle for
  a trade at zero.
- Mark activeLiquidity=0 as OUT OF RANGE and show last execution separately
  from any current executable quote. Do not claim the token globally is zero.
- If historical quote-to-USD rates are missing, show WETH quote units rather
  than convert historical swaps using the latest ETH price.
- The 24h percentage is unavailable without a recent trade and a backed
  anchor trade. Token-wide market cap remains independent of this pool.
- Current buy/sell prices must come from the on-chain quoter at the user's
  trade size; historical chart prices are not route quotes or oracle inputs.
## Website integration
This PR includes actual HTML/SVG candle rendering and a browser adapter.
Replace the old iframe container with an element such as #pool-chart, then
provide a backend snapshot using the existing reorg-aware indexer:
~~~js
import { refreshAbyssChart } from "./market-chart/browser-adapter.mjs";
async function refreshMarket(pool) {
  return refreshAbyssChart(document.querySelector("#pool-chart"), async () => {
    const r = await fetch("/api/markets/" + pool + "/executions", {cache:"no-store"});
    if (!r.ok) throw new Error("Chart data unavailable");
    return r.json();
  });
}
~~~
Expected response contains:
- market: chainId, pool, token0/token1, token0Decimals/token1Decimals,
  baseIndex (0 or 1), baseSymbol, quoteSymbol, displayCurrency ("usd"/"quote")
- swaps: signed amount0/amount1, canonical block/transaction log identity,
  timestamp, optionally quoteUsd from the *same timestamp* for USD candles
- state: activeLiquidity and tick from a fresh pinned-block contract read
Use an indexer and cache; do not scan millions of 0.1-second blocks from a
browser. Do not use any UI price as an executable quote or lending oracle.
## Acceptance criteria
After block 105505743, the USDG/WETH Abyss selected market shows a
**positive last-execution candle**, preserved no-trade gaps, an
**out-of-range** banner, **no fake zero candle or -100% from terminal
spot tick**, and no current executable spot quote. Separate healthy
USDG pools can retain nonzero token-wide valuations.
## Reproduce
~~~sh
node --test integration/market-chart/market-chart.test.mjs
python -m http.server 8765
# open http://localhost:8765/integration/market-chart/demo.html
~~~
The demo uses seven on-chain Swap event values with a static illustrative
USD conversion over 43 minutes. No trades are placed or contracts modified.