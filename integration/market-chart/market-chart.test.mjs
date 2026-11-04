import test from "node:test";
import assert from "node:assert/strict";
import {
  SWAP_TOPIC, decodeSwapLog, executionFromSwap, candleSeries,
  poolHealth, marketChartModel,
} from "./market-chart.mjs";
const market = {
  chainId: 4663,
  pool: "0xb39c61326bdba51586eac45f6bb418364fc65c92",
  token0: "0x0bd7d308f8e1639fab988df18a8011f41eacad73",
  token1: "0x3eb2984a7ef1c2e33f2d919db775b0f6e190fe16",
  token0Decimals:18,token1Decimals:18,baseIndex:1,
  baseSymbol:"USDG",quoteSymbol:"WETH",displayCurrency:"usd",
};
const eventTime = Date.parse("2026-11-04T01:11:02.000Z") / 1000;
const first = {
  timestamp:eventTime,chainId:4663,address:market.pool,quoteUsd:2247.91,
  blockNumber:105505742,blockHash:"0x"+"a".repeat(64),
  transactionHash:"0x7cc401d52531beb19bb811742fdfe55639f86f442c5de37c84f0269a074f2b33",
  logIndex:31,amount0:"-2116099287846550",amount1:"323829608200408338508848",
  liquidityAfter:"25351317897703506734310",tickAfter:188380,
};
const last = {
  timestamp:eventTime,chainId:4663,address:market.pool,quoteUsd:2247.91,
  blockNumber:105505743,blockHash:"0x"+"b".repeat(64),
  transactionHash:"0x8f1f11c129a4b2f1ed0fd074a7b9bfba4df66caa254fca82e87b26639b6ab610",
  logIndex:10,amount0:"-1952492291187482",amount1:"299389675986963248145871",
  liquidityAfter:"0",tickAfter:887271,
  sqrtPriceX96:"1461446703485210103287273052203988822378723970341",
};
test("decodes exact 2026 USDG boundary Swap event with signed 256-bit values",()=>{
  const enc=(value)=>BigInt.asUintN(256,BigInt(value)).toString(16).padStart(64,"0");
  const log={topics:[SWAP_TOPIC],data:"0x"+[
    last.amount0,last.amount1,last.sqrtPriceX96,last.liquidityAfter,last.tickAfter,
  ].map(enc).join(""),timestamp:last.timestamp};
  const r=decodeSwapLog(log);
  assert.equal(r.amount0,last.amount0);
  assert.equal(r.amount1,last.amount1);
  assert.equal(r.liquidityAfter,"0");
  assert.equal(r.tickAfter,887271);
});
test("USDG actual executed swap is ~$0.00001466, NOT $0",()=>{
  const r=executionFromSwap(last,market);
  assert.ok(r.priceUsd>0.000014&&r.priceUsd<0.000015);
  assert.equal(r.tickAfter,887271);
  assert.equal(r.activeLiquidityAfter,"0");
  const model=marketChartModel({market,swaps:[first,last],state:{activeLiquidity:"0"},nowSeconds:eventTime+3500});
  assert.equal(model.health.status,"out-of-range");
  assert.equal(model.candles.length,1);
  assert.ok(model.candles[0].close>0);
  assert.ok(model.candles[0].low>0);
  assert.equal(model.canDisplayLiveSpot,false);
  assert.equal(model.change24h,null);
});
test("inverted base/quote is correctly priced",()=>{
  const execution=executionFromSwap({...last,quoteUsd:undefined},
    {...market,baseIndex:0,baseSymbol:"WETH",quoteSymbol:"USDG"});
  assert.ok(execution.priceQuote>150000000&&execution.priceQuote<155000000);
  assert.equal(execution.priceUsd,null);
});
test("rejects wrong pool/chain, fake zero, invalid signs, missing timestamp, removed logs",()=>{
  assert.equal(executionFromSwap({...last,address:"0x"+"1".repeat(40)},market),null);
  assert.equal(executionFromSwap({...last,chainId:1},market),null);
  assert.equal(executionFromSwap({...last,amount0:"0"},market),null);
  assert.equal(executionFromSwap({...last,amount1:"-4"},market),null);
  assert.equal(executionFromSwap({...last,timestamp:undefined},market),null);
  assert.equal(executionFromSwap({...last,removed:true},market),null);
});
test("six-decimal quote values are normalized",()=>{
  const r=executionFromSwap({...last,quoteUsd:undefined,
    amount0:"-1000000000000000000",amount1:"1234567"},{
      ...market,baseIndex:0,token1Decimals:6,
    });
  assert.equal(r.priceQuote,1.234567);
});
test("deduplicates canonical log identities, preserves empty intervals",()=>{
  const a=executionFromSwap(first,market),b=executionFromSwap(last,market);
  const c={...b,id:"another",timestamp:eventTime+3600};
  const bars=candleSeries([a,b,c,a],900,"usd");
  assert.equal(bars.length,2);
  assert.equal(bars[0].trades,2);
  assert.equal(bars[1].time-bars[0].time,3600);
  assert.ok(bars.every(x=>x.open>0&&x.close>0));
});
test("pool liquidity 0 is out of range, invalid state fails closed",()=>{
  assert.equal(poolHealth({activeLiquidity:"0x0"}).status,"out-of-range");
  assert.equal(poolHealth({activeLiquidity:"0"}).status,"out-of-range");
  assert.equal(poolHealth({activeLiquidity:"100"}).hasActiveLiquidity,true);
  assert.equal(poolHealth({activeLiquidity:"bad"}).status,"unknown");
  assert.equal(poolHealth(null).status,"unknown");
});
test("do not display stale or unsupported 24h change",()=>{
  const anchor={...first,blockHash:"0x"+"c".repeat(64),
    timestamp:eventTime-86400,amount0:"-3000000000000000",
    amount1:"300000000000000000000000"};
  const recent=marketChartModel({market,swaps:[anchor,last],state:{activeLiquidity:"0"},nowSeconds:eventTime+60});
  assert.ok(Number.isFinite(recent.change24h));
  const stale=marketChartModel({market,swaps:[anchor,last],state:{activeLiquidity:"0"},nowSeconds:eventTime+4*3600});
  assert.equal(stale.change24h,null);
});
test("historical USD requires complete timestamp-aligned quote rate",()=>{
  const model=marketChartModel({market,swaps:[last,{...first,quoteUsd:undefined}],
    state:{activeLiquidity:"0"},nowSeconds:eventTime+60});
  assert.equal(model.priceUnit,"quote");
  assert.equal(model.currencyFallback,true);
});
test("market without swaps has unavailable price, never numeric zero",()=>{
  const model=marketChartModel({market,swaps:[],state:{activeLiquidity:"0"},nowSeconds:eventTime});
  assert.equal(model.lastTradePrice,null);
  assert.equal(model.candles.length,0);
  assert.equal(model.change24h,null);
});
test("bad event data is skipped without crashing candle series",()=>{
  const model=marketChartModel({market,swaps:[{...last,amount0:"garbage"},last],
    state:{activeLiquidity:"0"},nowSeconds:eventTime+60});
  assert.equal(model.candles.length,1);
  assert.equal(model.candles[0].trades,1);
});
test("timeframes reject invalid bar widths",()=>{
  assert.throws(()=>candleSeries([],0),TypeError);
  assert.throws(()=>candleSeries([],-1),TypeError);
});