import test from "node:test";
import assert from "node:assert/strict";
import {
  PERIODS, dexscreenerEmbed, isDexscreenerUrl, selectedDefaultMode,
  vettedReference, asTerminalModel, sma, ema, vwap, rsi,
  chartData, formatExecution,
} from "./terminal-core.mjs";
const selectedPool="0xb39c61326bdba51586eac45f6bb418364fc65c92";
const original="https://dexscreener.com/robinhood/"+selectedPool;
test("official DexScreener iframe is retained as an option",()=>{
  const url=dexscreenerEmbed(original);
  assert.match(url,/dexscreener.com/);
  assert.match(url,/embed=1/);
  assert.match(url,/theme=dark/);
});
test("blocks javascript, data, arbitrary hosts, mismatched iframe paths",()=>{
  for (const input of [
    "javascript:alert(1)", "http://dexscreener.com/robinhood/"+selectedPool,
    "https://dexscreener.com.evil.com/robinhood/"+selectedPool,
    "https://example.com/robinhood/"+selectedPool,
    "data:text/html,<script>alert(1)</script>",
    "https://dexscreener.com/robinhood/abc/../../evil",
  ]) assert.equal(isDexscreenerUrl(input),false);
});
test("zero/unknown active liquidity defaults to verified trades, active to native Dex",()=>{
  assert.equal(selectedDefaultMode({status:"out-of-range"},original),"verified");
  assert.equal(selectedDefaultMode({status:"unknown"},original),"verified");
  assert.equal(selectedDefaultMode({status:"active"},original),"dex");
  assert.equal(selectedDefaultMode({status:"active"},null),"verified");
});
test("reference venue must be separately labeled, active and different",()=>{
  const safe={
    url:"https://dexscreener.com/robinhood/0x"+"a".repeat(40),
    pool:"0x"+"a".repeat(40),hasActiveLiquidity:true,
    venue:"Other DEX",baseSymbol:"USDG",quoteSymbol:"WETH",
  };
  const actual=vettedReference(safe,selectedPool);
  assert.equal(actual.venue,"Other DEX");
  assert.equal(actual.pair,"USDG/WETH");
  assert.equal(vettedReference({...safe,hasActiveLiquidity:false},selectedPool),null);
  assert.equal(vettedReference({...safe,pool:selectedPool},selectedPool),null);
  assert.equal(vettedReference({...safe,url:"https://example.com/"},selectedPool),null);
});
test("supports all six real interval mappings and rejects unsupported",()=>{
  assert.deepEqual(Object.values(PERIODS),[60,300,900,3600,14400,86400]);
  assert.throws(()=>asTerminalModel({}, "13m"),TypeError);
});
const candles=Array.from({length:34},(_,i)=>({
  time:1700000000+i*900,open:10+i,close:10+i,
  high:11+i,low:9+i,baseVolume:10,quoteVolume:100+i,
}));
test("SMA20 uses actual closing values",()=>{
  const bars=sma(candles);
  assert.equal(bars.length,15);
  assert.equal(bars[0].value,19.5);
});
test("EMA20 is correctly seeded from first 20 closes",()=>{
  const bars=ema(candles);
  assert.equal(bars.length,15);
  assert.equal(bars[0].value,19.5);
  assert.ok(bars[1].value>bars[0].value);
});
test("RSI14 for rising series stays near 100 without NaNs",()=>{
  const bars=rsi(candles);
  assert.equal(bars.length,20);
  assert.ok(bars.every((b)=>Number.isFinite(b.value)&&b.value===100));
});
test("VWAP uses execution quote notional divided by executed base volume",()=>{
  const bars=vwap(candles);
  assert.equal(bars.length,candles.length);
  assert.ok(bars.every((b)=>Number.isFinite(b.value)&&b.value>0));
  assert.ok(bars.at(-1).value>bars[0].value);
});
test("chart data converts OHLC and volume without manufacturing extra bars",()=>{
  const result=chartData(candles);
  assert.equal(result.candles.length,candles.length);
  assert.equal(result.volumes.length,candles.length);
  assert.deepEqual(Object.keys(result.candles[0]),["time","open","high","low","close"]);
});
test("unavailable prices never appear as 0.0000",()=>{
  assert.equal(formatExecution(null),"Unavailable");
  assert.equal(formatExecution(0),"Unavailable");
  assert.equal(formatExecution(NaN),"Unavailable");
  assert.match(formatExecution(0.00001466),/0.00001466/);
});