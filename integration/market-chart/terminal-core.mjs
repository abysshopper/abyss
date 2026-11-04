import { marketChartModel } from "./market-chart.mjs";
export const PERIODS = Object.freeze({
  "1m": 60, "5m": 300, "15m": 900, "1h": 3600,
  "4h": 14400, "1D": 86400,
});
export function isDexscreenerUrl(input) {
  try {
    const url = new URL(input);
    return url.protocol === "https:" && ["dexscreener.com", "www.dexscreener.com"].includes(url.hostname)
      && /^\/[a-z0-9-]+\/[a-z0-9]+\/?$/i.test(url.pathname);
  } catch { return false; }
}
export function dexscreenerEmbed(input) {
  if (!isDexscreenerUrl(input)) return null;
  const url = new URL(input);
  url.search = "";
  url.searchParams.set("embed", "1");
  url.searchParams.set("theme", "dark");
  url.searchParams.set("info", "0");
  return url.toString();
}
export function selectedDefaultMode(health, dexUrl) {
  // Inactive/unknown liquidity is always protected by a verified-fills chart;
  // do not silently promote a broken DexScreener spot-price chart.
  return health?.status === "active" && dexscreenerEmbed(dexUrl) ? "dex" : "verified";
}
export function vettedReference(ref, selectedPool) {
  if (!ref?.url || !dexscreenerEmbed(ref.url)) return null;
  if (!ref.venue || !ref.baseSymbol || !ref.quoteSymbol || !ref.pool
      || !/^0x[0-9a-f]{40,64}$/i.test(ref.pool)) return null;
  if (String(ref.pool).toLowerCase() === String(selectedPool).toLowerCase()) return null;
  if (ref.hasActiveLiquidity !== true) return null;
  return {
    url: dexscreenerEmbed(ref.url),
    venue: String(ref.venue).slice(0, 80),
    pair: String(ref.baseSymbol).slice(0, 24) + "/" + String(ref.quoteSymbol).slice(0, 24),
    pool: String(ref.pool),
  };
}
export function asTerminalModel(snapshot, period = "15m") {
  if (!(period in PERIODS)) throw new TypeError("Invalid timeframe");
  return marketChartModel({ ...snapshot, timeframeSeconds: PERIODS[period] });
}
export function sma(candles, n = 20) {
  const result = [];
  let sum = 0;
  for (let i = 0; i < candles.length; i++) {
    sum += candles[i].close;
    if (i >= n) sum -= candles[i - n].close;
    if (i >= n - 1) result.push({ time: candles[i].time, value: sum / n });
  }
  return result;
}
export function ema(candles, n = 20) {
  if (candles.length < n) return [];
  let value = candles.slice(0, n).reduce((a, c) => a + c.close, 0) / n;
  const result = [{ time: candles[n - 1].time, value }];
  const alpha = 2 / (n + 1);
  for (let i = n; i < candles.length; i++) {
    value = alpha * candles[i].close + (1 - alpha) * value;
    result.push({ time: candles[i].time, value });
  }
  return result;
}
export function vwap(candles, priceUnit = "quote") {
  let volume = 0, notional = 0;
  const result = [];
  for (const c of candles) {
    const amount = Number(c.baseVolume);
    const quoteValue = Number(priceUnit === "usd" ? c.usdVolume : c.quoteVolume);
    if (!Number.isFinite(amount) || amount <= 0 || !Number.isFinite(quoteValue) || quoteValue <= 0) continue;
    // True executed volume-weighted average across Swap deltas, not
    // an OHLC typical-price approximation or terminal spot tick.
    volume += amount;
    notional += quoteValue;
    result.push({ time: c.time, value: notional / volume });
  }
  return result;
}
export function rsi(candles, n = 14) {
  if (candles.length <= n) return [];
  let gain = 0, loss = 0;
  for (let i = 1; i <= n; i++) {
    const diff = candles[i].close - candles[i - 1].close;
    gain += Math.max(diff, 0);
    loss += Math.max(-diff, 0);
  }
  gain /= n; loss /= n;
  const calc = () => gain === 0 && loss === 0 ? 50
    : loss === 0 ? 100 : 100 - (100 / (1 + gain / loss));
  const result = [{ time: candles[n].time, value: calc() }];
  for (let i = n + 1; i < candles.length; i++) {
    const diff = candles[i].close - candles[i - 1].close;
    gain = (gain * (n - 1) + Math.max(diff, 0)) / n;
    loss = (loss * (n - 1) + Math.max(-diff, 0)) / n;
    result.push({ time: candles[i].time, value: calc() });
  }
  return result;
}
export function chartData(candles) {
  return {
    candles: candles.map(({ time, open, high, low, close }) => ({ time, open, high, low, close })),
    volumes: candles.map(({ time, quoteVolume, close, open }) => ({
      time, value: quoteVolume, color: close >= open ? "rgba(18,184,164,.7)" : "rgba(235,83,94,.7)",
    })),
  };
}
export function formatExecution(value) {
  if (!Number.isFinite(value) || value <= 0) return "Unavailable";
  if (value >= 1) return value.toLocaleString("en-US", { maximumFractionDigits: 6 });
  return value.toPrecision(6);
}