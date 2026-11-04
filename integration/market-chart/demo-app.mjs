import { mountAbyssTerminal } from "./trading-terminal.mjs";
const pool = "0xb39c61326bdba51586eac45f6bb418364fc65c92";
const market = {
  chainId:4663, pool,
  token0:"0x0bd7d308f8e1639fab988df18a8011f41eacad73",
  token1:"0x3eb2984a7ef1c2e33f2d919db775b0f6e190fe16",
  token0Decimals:18, token1Decimals:18, baseIndex:1,
  baseSymbol:"USDG", quoteSymbol:"WETH", displayCurrency:"usd",
};
const event = (timestamp,blockNumber,amount0,amount1,tickAfter,liquidityAfter) => ({
  timestamp,blockNumber,address:pool,chainId:4663,amount0,amount1,
  tickAfter,liquidityAfter,quoteUsd:2247.91,
});
const swaps = [
  event("2026-11-04T00:28:56Z",105480816,"-2116611106429602","322821176279362078937076",188347,"25351317897703506734310"),
  event("2026-11-04T00:28:56Z",105480817,"-2461496090285277","376265266689437422910849",188371,"25351317897703506734310"),
  event("2026-11-04T00:30:55Z",105482011,"-2918823454231620","447351537236737378110953",188399,"25351317897703506734310"),
  event("2026-11-04T01:05:40Z",105502583,"3295861107677182","-495010104675209521103872",188368,"25351317897703506734310"),
  event("2026-11-04T01:05:55Z",105502732,"854118425003856","-128025514393644220362898",188360,"25351317897703506734310"),
  event("2026-11-04T01:11:02Z",105505742,"-2116099287846550","323829608200408338508848",188380,"25351317897703506734310"),
  event("2026-11-04T01:11:02Z",105505743,"-1952492291187482","299389675986963248145871",887271,"0"),
];
const snapshot = {market,swaps,state:{activeLiquidity:"0",tick:887271},
  timeframeSeconds:900,nowSeconds:Date.parse("2026-11-04T04:08:00Z")/1000,
};
window.__abyssTerminal = await mountAbyssTerminal(
  document.getElementById("market-terminal"),{
    loadSnapshot:async()=>snapshot,
    dexscreenerUrl:"https://dexscreener.com/robinhood/"+pool,
    pollMs:0,
  });
window.__abyssReady = true;