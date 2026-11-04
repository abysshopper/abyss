import { refreshAbyssChart } from "./browser-adapter.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import {
  SWAP_TOPIC, decodeSwapLog, executionFromSwap, candleSeries,
  poolHealth, marketChartModel, renderMarketChart,
} from "./market-chart.mjs";
const market = {
  chainId: 4663,
  pool: "0xb39c61326bdba51586eac45f6bb418364fc65c92",
  token0: "0x0bd7d308f8e1639fab988df18a8011f41eacad73", // WETH
  token1: "0x3eb2984a7ef1c2e33f2d919db775b0f6e190fe16", // USDG
  token0Decimals: 18, token1Decimals: 18, baseIndex: 1,
  baseSymbol: "USDG", quoteSymbol: "WETH",
  displayCurrency: "usd",
};
const eventTime = Date.parse("2026-11-04T01:11:02.000Z") / 1000;
const first = {
  timestamp: eventTime, chainId: 4663, address: market.pool, quoteUsd: 2247.91,
  blockNumber: 105505742, blockHash: "0x" + "a".repeat(64),
  transactionHash: "0x7cc401d52531beb19bb811742fdfe55639f86f442c5de37c84f0269a074f2b33",
  logIndex: 31, amount0: "-2116099287846550",
  amount1: "323829608200408338508848", liquidityAfter: "25351317897703506734310",
  tickAfter: 188380,
};
const last = {
  timestamp: eventTime, chainId: 4663, address: market.pool, quoteUsd: 2247.91,
  quoteUsd: 2247.91, blockNumber: 105505743, blockHash: "0x" + "b".repeat(64),
  transactionHash: "0x8f1f11c129a4b2f1ed0fd074a7b9bfba4df66caa254fca82e87b26639b6ab610",
  logIndex: 10, amount0: "-1952492291187482",
  amount1: "299389675986963248145871",
  // Actual pool swap event from 2026-11-04 01:11:02 UTC:
  sqrtPriceX96: "1461446703485210103287273052203988822378723970341",
  liquidityAfter: "0", tickAfter: 887271,
};
test("decodes the real end-of-range Swap event, including signed 256-bit deltas", () => {
  const enc = (value) => BigInt.asUintN(256, BigInt(value)).toString(16).padStart(64, "0");
  const decoded = decodeSwapLog({
    topics: [SWAP_TOPIC],
    data: "0x" + [
      last.amount0, last.amount1, last.sqrtPriceX96, last.liquidityAfter,
      last.tickAfter,
    ].map(enc).join(""),
    timestamp: last.timestamp,
  });
  assert.equal(decoded.amount0, last.amount0);
  assert.equal(decoded.amount1, last.amount1);
  assert.equal(decoded.liquidityAfter, "0");
  assert.equal(decoded.tickAfter, 887271);
});
test("USDG extreme post-swap tick never becomes a zero-price candle", () => {
  const execution = executionFromSwap(last, market);
  assert.ok(execution.priceUsd > 0.000014 && execution.priceUsd < 0.000015);
  assert.equal(execution.activeLiquidityAfter, "0");
  assert.equal(execution.tickAfter, 887271);
  const model = marketChartModel({
    market, swaps: [first, last],
    state: { activeLiquidity: "0", tick: 887271 },
    nowSeconds: eventTime + 3 * 3600,
  });
  assert.equal(model.health.status, "out-of-range");
  assert.equal(model.canDisplayLiveSpot, false);
  assert.equal(model.candles.length, 1);
  assert.ok(model.candles[0].low > 0);
  assert.ok(model.lastTradePrice > 0);
  assert.equal(model.change24h, null);
  const html = renderMarketChart(model);
  assert.match(html, /data-price-source="executed-swaps"/);
  assert.match(html, /Out of range ΓÇö zero active liquidity/);
  assert.doesNotMatch(html, /-100%|Last execution:\s*0(?:\.0+)?\s/);
});
test("chart pricing correctly reverses base/quote orientation", () => {
  const reversed = { ...market, baseIndex: 0, baseSymbol: "WETH", quoteSymbol: "USDG", quoteUsd: undefined };
  const execution = executionFromSwap({ ...last, quoteUsd: undefined }, reversed);
  assert.ok(execution.priceQuote > 150_000_000 && execution.priceQuote < 155_000_000);
  assert.equal(execution.priceUsd, null);
});
test("rejects wrong pool, chain, invalid directions, missing timestamps, and dust", () => {
  assert.equal(executionFromSwap({ ...last, address: "0x" + "a".repeat(40) }, market), null);
  assert.equal(executionFromSwap({ ...last, chainId: 1 }, market), null);
  assert.equal(executionFromSwap({ ...last, amount0: "0" }, market), null);
  assert.equal(executionFromSwap({ ...last, amount1: "-20" }, market), null);
  assert.equal(executionFromSwap({ ...last, timestamp: undefined }, market), null);
  assert.equal(executionFromSwap({ ...last, removed: true }, market), null);
});
test("honors six-decimal quotes without converting huge raw BigInts to Number first", () => {
  const six = { ...market, baseIndex: 0, token0Decimals: 18, token1Decimals: 6, quoteUsd: undefined };
  const event = { ...last, quoteUsd: undefined, amount0: "-1000000000000000000", amount1: "1234567" };
  assert.equal(executionFromSwap(event, six).priceQuote, 1.234567);
});
test("deduplicates canonical events and leaves no-trade time gaps (never fills with zero)", () => {
  const a = executionFromSwap(first, market);
  const b = executionFromSwap(last, market);
  const later = { ...b, id: "another-event", timestamp: eventTime + 3600 };
  const candles = candleSeries([later, b, a, a], 900, "usd");
  assert.equal(candles.length, 2);
  assert.equal(candles[0].trades, 2);
  assert.equal(candles[1].trades, 1);
  assert.equal(candles[1].time - candles[0].time, 3600);
  assert.ok(candles.every((c) => c.open > 0 && c.close > 0));
});
test("zero liquidity means out of range, not a trustworthy spot quote", () => {
  assert.equal(poolHealth({ activeLiquidity: 0 }).status, "out-of-range");
  assert.equal(poolHealth({ activeLiquidity: "0x0" }).status, "out-of-range");
  assert.equal(poolHealth({ activeLiquidity: "100" }).hasActiveLiquidity, true);
  assert.equal(poolHealth({ activeLiquidity: "garbage" }).status, "unknown");
  assert.equal(poolHealth(undefined).status, "unknown");
});
test("24h change must have a recent last trade and a real nearby reference trade", () => {
  const anchor = { ...first, timestamp: eventTime - 86400, blockHash: "0x" + "c".repeat(64),
    amount0: "-3000000000000000", amount1: "300000000000000000000000" };
  const recent = marketChartModel({
    market, swaps: [anchor, last], state: { activeLiquidity: "0" },
    nowSeconds: eventTime + 60,
  });
  assert.ok(recent.change24h !== null && Number.isFinite(recent.change24h));
  const stale = marketChartModel({
    market, swaps: [anchor, last], state: { activeLiquidity: "0" },
    nowSeconds: eventTime + 4 * 3600,
  });
  assert.equal(stale.change24h, null);
});
test("unknown pool state fails closed and HTML-escapes untrusted token symbols", () => {
  const model = marketChartModel({
    market: { ...market, baseSymbol: "<img src=x onerror=alert(1)>" },
    swaps: [last], state: null, nowSeconds: eventTime + 2,
  });
  const html = renderMarketChart(model);
  assert.match(html, /Pool state unavailable/);
  assert.doesNotMatch(html, /<img/);
  assert.match(html, /&lt;img/);
});
test("no executions renders unavailable, not zero", () => {
  const model = marketChartModel({
    market, swaps: [], state: { activeLiquidity: "0" }, nowSeconds: eventTime,
  });
  assert.equal(model.lastTradePrice, null);
  const html = renderMarketChart(model);
  assert.match(html, /No valid executed trades/);
  assert.doesNotMatch(html, /Last execution:\s*0(?:\.0+)?\s/);
});test("adapter actually replaces the chart container rather than merely adding a warning", async () => {
  const container = { innerHTML: "OLD DEXSCREENER IFRAME", dataset: {} };
  const model = await refreshAbyssChart(container, async () => ({
    market, swaps: [first, last], state: { activeLiquidity: "0", tick: 887271 },
    nowSeconds: eventTime + 3600,
  }));
  assert.equal(container.dataset.abyssChartStatus, "out-of-range");
  assert.ok(container.innerHTML.includes("<svg"));
  assert.ok(container.innerHTML.includes("Out of range"));
  assert.ok(container.innerHTML.includes("executed trades"));
  assert.ok(model.lastTradePrice > 0);
  assert.doesNotMatch(container.innerHTML, /DEXSCREENER IFRAME|-100%/);
});
test("USD mode without historical FX falls back to WETH, not a synthetic USD series", () => {
  const raw = { ...last, quoteUsd: undefined };
  const model = marketChartModel({
    market, swaps: [raw], state: { activeLiquidity: "0" },
    nowSeconds: eventTime + 20,
  });
  assert.equal(model.priceUnit, "quote");
  assert.equal(model.currencyFallback, true);
  assert.match(renderMarketChart(model), /Historical quote\/USD prices unavailable/);
});