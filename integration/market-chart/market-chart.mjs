/**
 * Executed-swap candle feed for Abyss v3-compatible markets.
 *
 * A post-swap sqrtPriceX96 at MIN/MAX_TICK is not an execution price.
 * It is particularly misleading when the trade crossed the last active range.
 * This module deliberately never turns that state into a price candle.
 *
 * This is DISPLAY DATA, not an executable quote or oracle.
 */
export const SWAP_TOPIC =
  "0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67";
const lower = (value) => String(value ?? "").toLowerCase();
const positiveFinite = (value) => typeof value === "number" && Number.isFinite(value) && value > 0;
function address(value) {
  if (!/^0x[0-9a-f]{40}$/i.test(value ?? "")) {
    throw new TypeError("Expected a 20-byte token/pool address");
  }
  return lower(value);
}
function amountToNumber(amount, decimals) {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 36) {
    throw new TypeError("Token decimals must be an integer from 0 to 36");
  }
  const absolute = amount < 0n ? -amount : amount;
  const unit = 10n ** BigInt(decimals);
  const whole = absolute / unit;
  const fraction = (absolute % unit).toString().padStart(decimals, "0");
  // Keep fractional precision useful for the chart without converting massive
  // 18-decimal integers to Number first.
  return Number(decimals ? whole.toString() + "." + fraction : whole.toString());
}
function timestampSeconds(value) {
  if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) return value;
  if (typeof value === "string" && /^\d+$/.test(value)) return timestampSeconds(Number(value));
  const millis = Date.parse(value);
  return Number.isFinite(millis) ? Math.floor(millis / 1000) : null;
}
function hexWord(data, index) {
  return BigInt("0x" + data.slice(2 + index * 64, 2 + (index + 1) * 64));
}
/**
 * Decode a canonical Uniswap v3-compatible Swap event returned by an indexer.
 * The indexer MUST attach block timestamp and canonical log identity.
 * eth_getLogs by itself does not contain a timestamp.
 */
export function decodeSwapLog(log) {
  if (lower(log?.topics?.[0]) !== SWAP_TOPIC || !/^0x[0-9a-f]{320}$/i.test(log?.data ?? "")) {
    return null;
  }
  return {
    ...log,
    amount0: BigInt.asIntN(256, hexWord(log.data, 0)).toString(),
    amount1: BigInt.asIntN(256, hexWord(log.data, 1)).toString(),
    sqrtPriceX96: hexWord(log.data, 2).toString(),
    liquidityAfter: hexWord(log.data, 3).toString(),
    tickAfter: Number(BigInt.asIntN(24, hexWord(log.data, 4))),
    timestamp: log.timestamp ?? log.blockTimestamp,
  };
}
function validatedMarket(market) {
  if (!market || ![0, 1].includes(market.baseIndex)) {
    throw new TypeError("Expected baseIndex 0 or 1 for this specific pool");
  }
  const token0 = address(market.token0);
  const token1 = address(market.token1);
  const pool = address(market.pool);
  if (token0 === token1) throw new TypeError("Pair tokens must be distinct");
  return {
    token0,
    token1,
    pool,
    chainId: Number(market.chainId),
    baseIndex: market.baseIndex,
    baseDecimals: market.baseIndex === 0 ? market.token0Decimals : market.token1Decimals,
    quoteDecimals: market.baseIndex === 0 ? market.token1Decimals : market.token0Decimals,
    displayCurrency: market.displayCurrency ?? "quote",
    baseSymbol: market.baseSymbol ?? "Base",
    quoteSymbol: market.quoteSymbol ?? "Quote",
  };
}
export function executionFromSwap(input, market) {
  const m = validatedMarket(market);
  const swap = input?.topics ? decodeSwapLog(input) : input;
  if (!swap || swap.removed || (swap.address && lower(swap.address) !== m.pool)) return null;
  if (swap.chainId != null && Number(swap.chainId) !== m.chainId) return null;
  try {
    const amount0 = BigInt(swap.amount0);
    const amount1 = BigInt(swap.amount1);
    // A swap must exchange two opposite-sign token deltas. Ignore zero/dust
    // or malformed events instead of manufacturing a zero candle.
    if (amount0 === 0n || amount1 === 0n || (amount0 > 0n) === (amount1 > 0n)) return null;
    const baseAmount = m.baseIndex === 0 ? amount0 : amount1;
    const quoteAmount = m.baseIndex === 0 ? amount1 : amount0;
    const base = amountToNumber(baseAmount, m.baseDecimals);
    const quote = amountToNumber(quoteAmount, m.quoteDecimals);
    const priceQuote = quote / base;
    if (!positiveFinite(priceQuote) || !positiveFinite(base) || !positiveFinite(quote)) return null;
    const timestamp = timestampSeconds(swap.timestamp ?? swap.blockTimestamp);
    if (timestamp === null) return null;
    const quoteUsd = positiveFinite(swap.quoteUsd) ? swap.quoteUsd : null;
    const priceUsd = quoteUsd === null ? null : priceQuote * quoteUsd;
    if (priceUsd !== null && !positiveFinite(priceUsd)) return null;
    const blockNumber = swap.blockNumber == null ? null : Number(swap.blockNumber);
    const logIndex = swap.logIndex == null ? null : Number(swap.logIndex);
    const txHash = lower(swap.transactionHash ?? swap.txHash ?? "");
    const blockHash = lower(swap.blockHash ?? "");
    const id = blockHash && txHash && Number.isInteger(logIndex)
      ? m.chainId + ":" + blockHash + ":" + txHash + ":" + logIndex
      : null;
    return {
      timestamp, blockNumber, logIndex, txHash, id,
      priceQuote, priceUsd, baseVolume: base, quoteVolume: quote,
      // Quote-side and execution price are not mid-market prices.
      direction: baseAmount > 0n ? "sell" : "buy",
      tickAfter: swap.tickAfter == null ? null : Number(swap.tickAfter),
      activeLiquidityAfter: swap.liquidityAfter == null ? null : String(swap.liquidityAfter),
    };
  } catch {
    return null;
  }
}
export function poolHealth(state) {
  if (state?.activeLiquidity == null) {
    return { status: "unknown", hasActiveLiquidity: false, reason: "Pool state unavailable" };
  }
  try {
    if (BigInt(state.activeLiquidity) === 0n) {
      return { status: "out-of-range", hasActiveLiquidity: false, reason: "No active in-range liquidity" };
    }
    if (BigInt(state.activeLiquidity) > 0n) {
      return { status: "active", hasActiveLiquidity: true, reason: null };
    }
  } catch { /* Invalid/absent state must fail closed. */ }
  return { status: "unknown", hasActiveLiquidity: false, reason: "Invalid active-liquidity state" };
}
export function candleSeries(executions, timeframeSeconds = 900, priceUnit = "quote") {
  if (!Number.isInteger(timeframeSeconds) || timeframeSeconds <= 0) {
    throw new TypeError("timeframeSeconds must be a positive integer");
  }
  const field = priceUnit === "usd" ? "priceUsd" : "priceQuote";
  const sorted = [...executions].filter((trade) => positiveFinite(trade[field]))
    .sort((a, b) => a.timestamp - b.timestamp || (a.blockNumber ?? 0) - (b.blockNumber ?? 0)
      || (a.logIndex ?? 0) - (b.logIndex ?? 0));
  const seen = new Set();
  const candles = [];
  let candle;
  for (const trade of sorted) {
    if (trade.id) {
      if (seen.has(trade.id)) continue;
      seen.add(trade.id);
    }
    const time = Math.floor(trade.timestamp / timeframeSeconds) * timeframeSeconds;
    const price = trade[field];
    if (!candle || candle.time !== time) {
      candle = { time, open: price, high: price, low: price, close: price,
        baseVolume: 0, quoteVolume: 0, trades: 0 };
      candles.push(candle);
    }
    candle.high = Math.max(candle.high, price);
    candle.low = Math.min(candle.low, price);
    candle.close = price;
    candle.baseVolume += trade.baseVolume;
    candle.quoteVolume += trade.quoteVolume;
    candle.trades++;
  }
  // Deliberately do not fill no-trade intervals with zero-priced candles.
  return candles;
}
export function marketChartModel({
  market, swaps, state, nowSeconds = Math.floor(Date.now() / 1000),
  timeframeSeconds = 900, referenceWindowSeconds = 3600,
}){
  const m = validatedMarket(market);
  const events = (swaps ?? []).map((swap) => executionFromSwap(swap, market)).filter(Boolean);
  const useUsd = m.displayCurrency === "usd" && events.length > 0 && events.every((e) => positiveFinite(e.priceUsd));
  const priceUnit = useUsd ? "usd" : "quote";
  const candles = candleSeries(events, timeframeSeconds, priceUnit);
  const last = candles.at(-1) ?? null;
  const status = poolHealth(state);
  const changeTime = nowSeconds - 86400;
  const reference = [...candles].reverse().find((c) =>
    c.time <= changeTime && c.time >= changeTime - referenceWindowSeconds);
  const latestIsRecent = last && last.time <= nowSeconds &&
    nowSeconds - last.time <= Math.max(1800, timeframeSeconds * 2);
  const change24h = latestIsRecent && reference && reference.close > 0
    ? ((last.close / reference.close) - 1) * 100
    : null;
  return {
    market: m, candles, last, change24h, priceUnit, timeframeSeconds,
    currencyFallback: m.displayCurrency === "usd" && !useUsd,
    health: status,
    // Never use the extreme spot sqrtPriceX96 as a token valuation.
    lastTradePrice: last?.close ?? null,
    lastTradeTimestamp: last?.time ?? null,
    canDisplayLiveSpot: status.hasActiveLiquidity,
    mustRequestFreshSwapQuote: true,
    priceSource: "Abyss Swap event execution ratio",
    note: "This chart shows executed trade prices, not mid-market spot or a guaranteed executable quote.",
  };
}
function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}
function priceText(price) {
  if (!positiveFinite(price)) return "ΓÇö";
  return price >= 1 ? price.toLocaleString("en-US", { maximumFractionDigits: 8 })
    : price.toPrecision(6);
}
/**
 * Drop-in SVG chart HTML. Render into the chart container INSTEAD of the
 * DexScreener iframe for native Abyss pools. Works without a chart dependency.
 */
export function renderMarketChart(model, { width = 860, height = 375 } = {}) {
  const w = Math.max(320, width), h = Math.max(220, height);
  const plotX = 65, plotY = 25, plotW = w - 95, plotH = h - 80;
  const series = model.candles.slice(-300);
  const minT = series[0]?.time ?? 0;
  const maxT = series.at(-1)?.time ?? minT;
  const lo = Math.min(...series.map((c) => c.low), Infinity);
  const hi = Math.max(...series.map((c) => c.high), -Infinity);
  const range = positiveFinite(hi - lo) ? hi - lo : Math.max(Math.abs(hi) * 0.04, 1e-15);
  const yLo = Math.max(0, lo - range * 0.12), yHi = hi + range * 0.12;
  const y = (p) => plotY + plotH * (1 - (p - yLo) / (yHi - yLo));
  const x = (time) => plotX + plotW * (time - minT + 0.5 * model.timeframeSeconds) / Math.max(model.timeframeSeconds, maxT - minT + model.timeframeSeconds);
  const candleWidth = Math.min(12, Math.max(2, plotW / Math.max(2, series.length) * 0.65));
  const lines = [0, 1, 2, 3, 4].map((i) => {
    const v = yLo + (yHi - yLo) * (1 - i / 4);
    const yy = plotY + (plotH * i / 4);
    return '<line x1="' + plotX + '" x2="' + (plotX + plotW) + '" y1="' + yy +
      '" y2="' + yy + '" stroke="#28333c"/><text x="5" y="' + (yy + 4) +
      '" font-size="11" fill="#adb9c0">' + escapeHtml(priceText(v)) + '</text>';
  }).join("");
  const candles = series.map((c) => {
    const cx = x(c.time), green = c.close >= c.open;
    const color = green ? "#13b9a6" : "#f65b67";
    const top = y(Math.max(c.open, c.close));
    const bh = Math.max(1.5, Math.abs(y(c.open) - y(c.close)));
    return '<line x1="' + cx + '" y1="' + y(c.high) + '" x2="' + cx +
      '" y2="' + y(c.low) + '" stroke="' + color + '" stroke-width="1.5"/>' +
      '<rect x="' + (cx - candleWidth / 2) + '" y="' + top +
      '" width="' + candleWidth + '" height="' + bh + '" fill="' + color + '"/>';
  }).join("");
  const title = escapeHtml(model.market.baseSymbol + "/" + model.market.quoteSymbol);
  const priceLabel = model.priceUnit === "usd" ? "USD" : escapeHtml(model.market.quoteSymbol);
  const banner = model.health.status === "out-of-range"
    ? '<p class="abyss-chart-warning" role="status">Out of range ΓÇö zero active liquidity. No current executable pool price. Historical candles are executed swap prices.</p>'
    : model.health.status === "unknown"
      ? '<p class="abyss-chart-warning" role="status">Pool state unavailable. Verify live liquidity and get a fresh quote before trading.</p>'
      : "";
  const change = model.change24h === null ? "ΓÇö" : model.change24h.toFixed(2) + "%";
  return '<section class="abyss-safe-chart" data-price-source="executed-swaps" data-pool-status="' +
    escapeHtml(model.health.status) + '">' +
    '<header><strong>' + title + ' ΓÇö executed trades</strong> <span>Last execution: ' +
    escapeHtml(priceText(model.lastTradePrice)) + ' ' + priceLabel +
    ' &nbsp; | &nbsp; 24h: ' + escapeHtml(change) + '</span></header>' +
    banner + (model.currencyFallback ? '<p class="abyss-chart-warning" role="status">Historical quote/USD prices unavailable ΓÇö showing prices in the quote token instead.</p>' : "") +
    (series.length ? '<svg role="img" aria-label="' + title +
      ' executed-trade candlestick chart; gaps mean no trades" viewBox="0 0 ' + w + ' ' + h +
      '" preserveAspectRatio="xMidYMid meet">' +
      '<rect width="' + w + '" height="' + h + '" fill="#101821"/>' +
      lines + candles + '<text x="' + plotX + '" y="' + (h - 16) +
      '" font-size="12" fill="#adb9c0">' + escapeHtml(new Date(minT * 1000).toISOString()) +
      '</text><text x="' + (w - 220) + '" y="' + (h - 16) +
      '" font-size="12" fill="#adb9c0">' + escapeHtml(new Date(maxT * 1000).toISOString()) +
      '</text></svg>' : '<p>No valid executed trades in the selected range.</p>') +
    '<footer>Swap-event execution prices, not pool spot ticks. Do not use for swap quotes, NAV, or oracles.</footer></section>';
}