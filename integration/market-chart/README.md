# Abyss hybrid market terminal: DexScreener + TradingView
This PR upgrades the old minimal SVG reference to a real interactive
chart integration, keeping the original feature-rich DexScreener iframe
for pools with active liquidity. The selected-pool chart mode switches
to **TradingView Lightweight Charts 5.2.1** when active liquidity is
zero or not verified. That fallback uses actual executed Swap prices,
not the terminal post-swap pool tick.
- Active pool: original DexScreener iframe and full embedded toolset.
- Exhausted/unknown pool: TradingView canvas with real execution prices,
  warning about unexecutable pool state and no false zero candle.
- User may explicitly view the raw DexScreener feed, with warning.
- Optional separate active reference market via DexScreener: clearly
  labeled as a different pool; never silently replaces selected pool.
- No merging a token-wide valuation with selected-pool execution history.
## On-chain regression
Pool (Robinhood Chain 4663):
0xb39c61326bdba51586eac45f6bb418364fc65c92
November 4, 2026 at 01:11:02 UTC, block 105505743. A swap sold
299389.675986963248145871 USDG for 0.001952492291187482 WETH,
ending at tick 887271 and 0 active liquidity. The actual fill averaged
approximately $0.00001466/USDG at an illustrative $2247.91/WETH
reference. DexScreener instead produced a fake zero-price candle
from the terminal spot tick. Other USDG pools remained nonzero.
Trigger:
https://robinhoodchain.blockscout.com/tx/0x8f1f11c129a4b2f1ed0fd074a7b9bfba4df66caa254fca82e87b26639b6ab610
## Features
Healthy pool: retain the full original embedded DexScreener chart.
Verified fallback: TradingView canvas candlesticks, true executed-swap
OHLC, volume subplot, crosshair OHLC, axis pan and zoom, fullscreen,
PNG export, logarithmic scale, horizontal level drawing, live data
refresh preserving zoom/drawings, 1m/5m/15m/1h/4h/1D intervals,
SMA20, EMA20, execution-volume VWAP, RSI14, and optional comparison
with a separately labeled active market.
No-trade intervals are gaps, never fake zero prices. Missing quote/USD
history falls back to token-quote pricing. Stale 24h percent changes
are unavailable. The chart is not an executable quote or lending oracle.
The TradingView Lightweight Charts engine is open source (Apache-2.0).
It is NOT proprietary TradingView Advanced Charts with its 100+
indicators and full drawing suite; that product requires separate
access and licensing. TradingView attribution is embedded in the UI.
## Integration: actual website frontend required
This official public Abyss repository is a source disclosure plus
integration guide, not the private production website source.
Merging this PR alone does not patch abyss.trading or DexScreener.
The website maintainer must replace the existing chart container with
this module, supplied by a canonical reorg-aware pool data backend.
Example:
~~~js
import { mountAbyssTerminal } from "./trading-terminal.mjs";
const controller = await mountAbyssTerminal(
  document.getElementById("pool-chart"), {
    dexscreenerUrl: "https://dexscreener.com/robinhood/0x...",
    pollMs: 10000,
    loadSnapshot: async () => {
      const r = await fetch("/api/markets/0x.../verified-snapshot", {
        cache: "no-store"
      });
      if (!r.ok) throw new Error("Market data unavailable");
      return r.json();
    }
  }
);
// On route unmount:
controller.dispose();
~~~
The backend snapshot contains:
- market: chainId, canonical pool address, token0/token1 addresses,
  their decimals, baseIndex (0 or 1), symbols, displayCurrency
- swaps: signed amount0/amount1, chainId, address, blockHash,
  transactionHash, logIndex, blockNumber, block timestamp, optional
  timestamp-matched quoteUsd
- state: activeLiquidity and tick from a FRESH pinned-block read
- referenceMarket (optional): validated distinct pool address,
  DexScreener URL, venue, pair symbols, verified active liquidity
Construct the full pool identity from AbyssPoolCreated, not symbols
alone. Index finalized, reorg-aware Swap events and join actual
block timestamps. USD charts require a verified quote/USD rate
at each event timestamp; never use today's WETH/USD for past trades.
Never scan millions of fast blocks in the browser.
The trade form must independently quote the ACTUAL ROUTE/SIZE
through the on-chain quoter, including slippage and expiry limits.
A historical chart does not grant executable liquidity.
## Run / tests
From integration/market-chart:
~~~sh
npm ci
npm test
npm run build
npm run test:browser
npm run dev
~~~
Browser test uses Edge/Playwright, exercising actual TradingView
canvas rendering and controls, preserved drawing/zoom across refresh,
raw DexScreener override, healthy original embed, automatic
healthy-to-exhausted mode switching, and the USDG regression event.
The demo is a historical fixture (not live market data) and uses an
illustrative fixed WETH/USD rate across a brief 43-minute interval.
It does not submit trades.
## Scope
A third-party iframe cannot be modified from its parent page to
change DexScreener's candle calculation. This design instead retains
DexScreener for normal pools and selectively replaces the misleading
feed with a real TradingView-powered execution chart. It cannot
modify the actual Abyss website until integrated by its maintainers.