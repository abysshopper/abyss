import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chromium } from "playwright-core";
const port = 19786;
const cwd = new URL(".", import.meta.url).pathname.replace(/^\/([A-Z]:\/)/, "$1");
const chromeCandidates = [
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
];
const edge = chromeCandidates.find((item) => {
  try { return requireExists(item); } catch { return false; }
});
function requireExists(path) {
  const fs = process.getBuiltinModule("node:fs");
  return fs.existsSync(path);
}
if (!edge) throw new Error("Microsoft Edge missing; browser QA not executed");
const server = spawn(process.execPath, [
  "node_modules/vite/bin/vite.js", "--host", "127.0.0.1", "--port", String(port), "--strictPort",
], { cwd, windowsHide: true });
let browser;
const sleep = (n) => new Promise((resolve) => setTimeout(resolve, n));
try {
  let ready = false;
  for (let i=0; i < 35; i++) {
    try {
      const response = await fetch("http://127.0.0.1:" + port + "/");
      ready = response.ok;
      if (ready) break;
    } catch { /* boot */ }
    await sleep(200);
  }
  assert.ok(ready, "Vite server started");
  browser = await chromium.launch({ executablePath: edge, headless: true, args: ["--disable-gpu"] });
  const page = await browser.newPage({ viewport: { width: 1460, height: 940 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on("pageerror", (err) => errors.push(err.message));
  await page.goto("http://127.0.0.1:" + port + "/");
  await page.waitForFunction(() => window.__abyssReady === true, { timeout: 20_000 });
  const before = await page.evaluate(() => ({
    mode: document.querySelector(".abyss-terminal").dataset.chartMode,
    health: document.querySelector(".abyss-terminal").dataset.poolStatus,
    canvases: document.querySelectorAll(".terminal-canvas canvas").length,
    outOfRange: document.querySelector(".terminal-health").textContent.includes("ZERO ACTIVE LIQUIDITY"),
    bad100: document.querySelector(".abyss-terminal").textContent.includes("-100%"),
    iframe: Boolean(document.querySelector("iframe.terminal-embed")),
  }));
  console.log("INITIAL", JSON.stringify(before));
  assert.equal(before.mode, "verified");
  assert.equal(before.health, "out-of-range");
  assert.ok(before.canvases > 0, "Real TradingView canvas rendered");
  assert.equal(before.outOfRange, true);
  assert.equal(before.bad100, false);
  assert.equal(before.iframe, false);
  const sameCanvasAfterRefresh = await page.evaluate(async () => {
    const canvas = document.querySelector(".terminal-canvas canvas");
    await window.__abyssTerminal.refresh();
    return canvas === document.querySelector(".terminal-canvas canvas");
  });
  assert.equal(sameCanvasAfterRefresh, true, "Fresh updates preserve zoom, drawings and chart instance");  await page.getByRole("button", { name: "1m", exact: true }).click();
  assert.match(await page.locator(".terminal-btn.is-active").allTextContents().then((xs) => xs.join(",")), /1m/);
  await page.getByRole("button", { name: "EMA20", exact: true }).click();
  await page.getByRole("button", { name: "SMA20", exact: true }).click();
  await page.getByRole("button", { name: "VWAP", exact: true }).click();
  await page.getByRole("button", { name: "VOL", exact: true }).click();
  await page.getByRole("button", { name: "VOL", exact: true }).click();
  await page.getByRole("button", { name: "15m", exact: true }).click();
  await page.getByRole("button", { name: "RSI14", exact: true }).click();
  await page.getByRole("button", { name: "Log", exact: true }).click();
  await page.getByRole("button", { name: "+", exact: true }).click();
  await page.getByRole("button", { name: "ΓêÆ", exact: true }).click();
  await page.getByRole("button", { name: "Latest", exact: true }).click();
  await page.getByRole("button", { name: "Level", exact: true }).click();
  await page.locator(".terminal-canvas").click({ position: { x: 300, y: 190 } });
  await page.getByRole("button", { name: "Clear", exact: true }).click();
  await page.screenshot({ path: "terminal-verified-qa.png", fullPage: true });
  await page.getByRole("button", { name: /Raw DexScreener/ }).click();
  assert.equal(await page.locator(".abyss-terminal").getAttribute("data-chart-mode"), "dex");
  assert.ok((await page.locator("iframe.terminal-embed").getAttribute("src")).includes("dexscreener.com"));
  assert.match(await page.locator(".terminal-health").textContent(), /RAW FEED SELECTED/);
  await page.getByRole("button", { name: "Verified trades" }).click();
  assert.equal(await page.locator(".abyss-terminal").getAttribute("data-chart-mode"), "verified");
  const healthy = await page.evaluate(async () => {
    const { mountAbyssTerminal } = await import("/trading-terminal.mjs");
    const host = document.createElement("div");
    document.body.appendChild(host);
    const selected = window.__abyssTerminal.getSnapshot();
    const copy = { ...selected, state: { activeLiquidity:"1234",tick:188380 } };
    const controller = await mountAbyssTerminal(host, {
      loadSnapshot: async () => copy,
      dexscreenerUrl: "https://dexscreener.com/robinhood/" + selected.market.pool,
    });
    const mode = controller.getMode();
    const src = host.querySelector("iframe")?.getAttribute("src");
    controller.dispose(); host.remove();
    return { mode, src };
  });
  assert.equal(healthy.mode, "dex");
  assert.match(healthy.src, /dexscreener.com/);
  const transition = await page.evaluate(async () => {
    const { mountAbyssTerminal } = await import("/trading-terminal.mjs");
    const host = document.createElement("div");
    document.body.appendChild(host);
    const data = window.__abyssTerminal.getSnapshot();
    let active = true;
    const controller = await mountAbyssTerminal(host, {
      loadSnapshot: async () => ({
        ...data, state: { activeLiquidity: active ? "1000000000000" : "0", tick: active ? 188380 : 887271 }
      }),
      dexscreenerUrl: "https://dexscreener.com/robinhood/" + data.market.pool,
    });
    const before = controller.getMode();
    active = false;
    await controller.refresh();
    const after = controller.getMode();
    const canvas = Boolean(host.querySelector(".terminal-canvas canvas"));
    const rawEmbed = Boolean(host.querySelector("iframe.terminal-embed"));
    controller.dispose(); host.remove();
    return {before,after,canvas,rawEmbed};
  });
  assert.deepEqual(transition,{before:"dex",after:"verified",canvas:true,rawEmbed:false},
    "Healthy pool changing to zero liquidity must drop DexScreener iframe automatically");  assert.deepEqual(errors, [], "No browser JavaScript errors");
  console.log("PASS: TradingView UI, indicators, timeframes, drawings, zoom, exhausted-vs-healthy switching, original DexScreener iframe preserved.");
} finally {
  await browser?.close();
  server.kill();
}