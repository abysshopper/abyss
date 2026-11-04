import {
  createChart, CandlestickSeries, HistogramSeries, LineSeries, LineStyle, CrosshairMode
} from "lightweight-charts";
import {
  PERIODS, asTerminalModel, selectedDefaultMode, dexscreenerEmbed,
  vettedReference, sma, ema, vwap, rsi, chartData, formatExecution
} from "./terminal-core.mjs";
import "./terminal.css";
function button(label, className, title) {
  const el = document.createElement("button");
  el.type = "button";
  el.className = className;
  el.textContent = label;
  if (title) el.title = title;
  return el;
}
function textEl(tag, className, text) {
  const el = document.createElement(tag);
  el.className = className;
  el.textContent = text;
  return el;
}
function setActive(el, on) {
  el.classList.toggle("is-active", Boolean(on));
  el.setAttribute("aria-pressed", String(Boolean(on)));
}
/**
 * Hybrid market terminal:
 * - preserves official DexScreener chart, with all its features, for healthy pools;
 * - protects zero-active-liquidity pools by defaulting to TradingView Lightweight
 *   Charts based on executed Swap ratios, never the terminal spot tick.
 * - never silently substitutes an alternative venue or token price.
 *
 * It is a display layer. Trade quotes MUST come from the Abyss on-chain quoter.
 */
export async function mountAbyssTerminal(host, {
  loadSnapshot, dexscreenerUrl = null, pollMs = 0, initialPeriod = "15m",
} = {}) {
  if (!(host instanceof Element) || typeof loadSnapshot !== "function") {
    throw new TypeError("A DOM host and an async market snapshot loader are required");
  }
  if (!(initialPeriod in PERIODS)) throw new TypeError("Unknown initial timeframe");
  const root = document.createElement("section");
  root.className = "abyss-terminal";
  host.replaceChildren(root);
  const heading = document.createElement("header");
  heading.className = "terminal-header";
  const identity = document.createElement("div");
  identity.className = "terminal-market";
  const pairTitle = textEl("strong", "terminal-title", "Loading market");
  const venue = textEl("span", "terminal-venue", "Abyss ┬╖ Robinhood Chain");
  identity.append(pairTitle, venue);
  const stats = textEl("div", "terminal-stats", "Retrieving verified market stateΓÇª");
  heading.append(identity, stats);
  root.append(heading);
  const ribbon = textEl("div", "terminal-health", "");
  ribbon.setAttribute("role", "status");
  root.append(ribbon);
  const toolbar = document.createElement("nav");
  toolbar.className = "terminal-toolbar";
  toolbar.setAttribute("aria-label", "Chart controls");
  const modes = document.createElement("div");
  modes.className = "terminal-controls";
  const dexBtn = button("DexScreener", "terminal-btn", "Original third-party chart");
  const fillsBtn = button("Verified trades", "terminal-btn", "TradingView chart built from actual Swap executions");
  const refBtn = button("Reference venue", "terminal-btn", "A separate, explicitly labeled active pool");
  modes.append(dexBtn, fillsBtn, refBtn);
  const periods = document.createElement("div");
  periods.className = "terminal-controls";
  const periodButtons = new Map();
  for (const period of Object.keys(PERIODS)) {
    const el = button(period, "terminal-btn terminal-period");
    periods.append(el);
    periodButtons.set(period, el);
  }
  const indicators = document.createElement("div");
  indicators.className = "terminal-controls";
  const names = ["VOL", "SMA20", "EMA20", "VWAP", "RSI14"];
  const indicatorButtons = new Map();
  for (const name of names) {
    const el = button(name, "terminal-btn terminal-indicator");
    indicators.append(el);
    indicatorButtons.set(name, el);
  }
  const actions = document.createElement("div");
  actions.className = "terminal-controls";
  const drawBtn = button("Level", "terminal-btn", "Click the chart to place a horizontal price level");
  const clearBtn = button("Clear", "terminal-btn", "Remove drawn price levels");
  const zoomIn = button("+", "terminal-btn", "Zoom in");
  const zoomOut = button("ΓêÆ", "terminal-btn", "Zoom out");
  const liveBtn = button("Latest", "terminal-btn", "Scroll to most recent trade");
  const scaleBtn = button("Log", "terminal-btn", "Toggle logarithmic scale");
  const saveBtn = button("PNG", "terminal-btn", "Save chart screenshot");
  const fullBtn = button("Γ¢╢", "terminal-btn", "Fullscreen");
  const refreshBtn = button("Γå╗", "terminal-btn", "Refresh market state");
  actions.append(drawBtn, clearBtn, zoomOut, zoomIn, liveBtn, scaleBtn, saveBtn, fullBtn, refreshBtn);
  toolbar.append(modes, periods, indicators, actions);
  root.append(toolbar);
  const meta = document.createElement("div");
  meta.className = "terminal-chart-meta";
  const ohlc = textEl("span", "terminal-ohlc", "Move the crosshair over candles for OHLC");
  const source = textEl("span", "terminal-source", "Waiting for data");
  meta.append(ohlc, source);
  root.append(meta);
  const panel = document.createElement("div");
  panel.className = "terminal-panel";
  root.append(panel);
  const footer = document.createElement("footer");
  footer.className = "terminal-footer";
  const disclaimer = textEl("span", "", "Execution history is not a current executable quote or oracle. Route quotes require an on-chain simulation.");
  const attribution = document.createElement("a");
  attribution.href = "https://www.tradingview.com/";
  attribution.target = "_blank";
  attribution.rel = "noopener noreferrer";
  attribution.textContent = "Charts by TradingView";
  footer.append(disclaimer, attribution);
  root.append(footer);
  let disposed = false;
  let snapshot = null;
  let model = null;
  let selectedMode = null;
  let requestedMode = null;
  let currentPeriod = initialPeriod;
  let currentChart = null;
  let renderedPool = null;
  let candleSeries = null;
  let volumeSeries = null;
  let indicatorSeries = new Map();
  let drawnLevels = [];
  let drawing = false;
  let logarithmic = false;
  let poll = null;
  let refreshRequest = 0;
  let resizeObserver = null;
  const activeIndicators = new Set(["VOL"]);
  function modeEnabled(name) {
    if (name === "verified") return true;
    if (name === "dex") return Boolean(dexscreenerEmbed(dexscreenerUrl));
    if (name === "reference") return Boolean(
      vettedReference(snapshot?.referenceMarket, snapshot?.market?.pool));
    return false;
  }
  function updateControls() {
    const active = model?.health?.status === "active";
    const reference = vettedReference(snapshot?.referenceMarket, snapshot?.market?.pool);
    dexBtn.hidden = !modeEnabled("dex");
    refBtn.hidden = !reference;
    dexBtn.textContent = !active && modeEnabled("dex") ? "Raw DexScreener ΓÜá" : "DexScreener";
    setActive(dexBtn, selectedMode === "dex");
    setActive(fillsBtn, selectedMode === "verified");
    setActive(refBtn, selectedMode === "reference");
    for (const [name, el] of periodButtons) {
      el.disabled = selectedMode !== "verified";
      setActive(el, name === currentPeriod);
    }
    for (const [name, el] of indicatorButtons) {
      el.disabled = selectedMode !== "verified";
      setActive(el, activeIndicators.has(name));
    }
    for (const el of [drawBtn, clearBtn, zoomIn, zoomOut, liveBtn, scaleBtn, saveBtn]) {
      el.disabled = selectedMode !== "verified";
    }
    setActive(drawBtn, drawing);
    setActive(scaleBtn, logarithmic);
  }
  function closeChart() {
    resizeObserver?.disconnect(); resizeObserver = null;
    if (currentChart) { currentChart.remove(); currentChart = null; }
    candleSeries = null; volumeSeries = null;
    indicatorSeries.clear();
    drawnLevels = [];
  }
  function computeIndicator(name, candles) {
    switch (name) {
      case "SMA20": return sma(candles);
      case "EMA20": return ema(candles);
      case "VWAP": return vwap(candles, model.priceUnit);
      case "RSI14": return rsi(candles);
      default: return [];
    }
  }
  function syncIndicators() {
    if (!currentChart || !model) return;
    if (volumeSeries) volumeSeries.applyOptions({ visible: activeIndicators.has("VOL") });
    for (const name of ["SMA20", "EMA20", "VWAP", "RSI14"]) {
      let series = indicatorSeries.get(name);
      if (activeIndicators.has(name)) {
        if (!series) {
          const colors = { SMA20: "#f2bb64", EMA20: "#6eacff", "VWAP": "#c58bfe", RSI14: "#ffb470" };
          const isRsi = name === "RSI14";
          series = currentChart.addSeries(LineSeries, {
            color: colors[name], lineWidth: 1.5,
            priceLineVisible: false, lastValueVisible: !isRsi,
            ...(isRsi ? { priceFormat: { type:"price", precision:2, minMove:0.01 } } : {}),
          }, isRsi ? 2 : 0);
          indicatorSeries.set(name, series);
        }
        series.setData(computeIndicator(name, model.candles));
      } else if (series) {
        currentChart.removeSeries(series);
        indicatorSeries.delete(name);
      }
    }
  }
  function showVerified() {
    closeChart();
    panel.replaceChildren();
    const holder = document.createElement("div");
    holder.className = "terminal-canvas";
    panel.append(holder);
    currentChart = createChart(holder, {
      autoSize: true,
      height: Math.max(410, holder.clientHeight),
      layout: {
        background: { type: "solid", color: "#111923" },
        textColor: "#adb9c9", attributionLogo: false,
      },
      grid: {
        vertLines: { color: "#26313d", style: LineStyle.Dotted },
        horzLines: { color: "#26313d", style: LineStyle.Dotted },
      },
      crosshair: { mode: CrosshairMode.Normal },
      rightPriceScale: { borderColor: "#34404c", mode: logarithmic ? 1 : 0 },
      timeScale: { borderColor: "#34404c", timeVisible: true, secondsVisible: false,
        rightOffset: 6, barSpacing: 12 },
      handleScroll: { mouseWheel: true, pressedMouseMove: true, horzTouchDrag: true, vertTouchDrag: true },
      handleScale: { axisPressedMouseMove: true, axisDoubleClickReset: true,
        mouseWheel: true, pinch: true },
      localization: {
        priceFormatter: (value) => formatExecution(value),
      },
    });
    candleSeries = currentChart.addSeries(CandlestickSeries, {
      upColor: "#17bda5", downColor: "#f25464",
      wickUpColor: "#17bda5", wickDownColor: "#f25464",
      borderUpColor: "#17bda5", borderDownColor: "#f25464",
      priceLineVisible: true,
      priceFormat: { type: "price", precision: 10, minMove: 1e-10 },
    }, 0);
    volumeSeries = currentChart.addSeries(HistogramSeries, {
      priceFormat: { type: "volume" },
      priceLineVisible: false, lastValueVisible: false,
    }, 1);
    const data = chartData(model.candles);
    candleSeries.setData(data.candles);
    volumeSeries.setData(data.volumes);
    syncIndicators();
    currentChart.timeScale().fitContent();
    currentChart.subscribeCrosshairMove((param) => {
      if (!param.time) return;
      const bar = param.seriesData.get(candleSeries);
      if (!bar || !("open" in bar)) return;
      ohlc.textContent = "O " + formatExecution(bar.open) + " ┬╖ H " + formatExecution(bar.high)
        + " ┬╖ L " + formatExecution(bar.low) + " ┬╖ C " + formatExecution(bar.close);
    });
    currentChart.subscribeClick((param) => {
      if (!drawing || !param?.point || !candleSeries) return;
      const price = candleSeries.coordinateToPrice(param.point.y);
      if (!Number.isFinite(price) || price <= 0) return;
      drawnLevels.push(candleSeries.createPriceLine({
        price, color: "#e5b967", lineWidth: 1, lineStyle: LineStyle.Dashed,
        axisLabelVisible: true, title: "Level",
      }));
      drawing = false;
      updateControls();
    });
    source.textContent = "TradingView ┬╖ " + (model.priceUnit === "usd" ? "USD" : model.market.quoteSymbol)
      + " ┬╖ validated Swap executions";
    if (!model.candles.length) {
      ohlc.textContent = "No executed trades in the selected range";
    } else {
      ohlc.textContent = "Last trade " + formatExecution(model.lastTradePrice)
        + " " + (model.priceUnit === "usd" ? "USD" : model.market.quoteSymbol)
        + " ┬╖ " + new Date(model.lastTradeTimestamp * 1000).toLocaleString();
    }
  }
  function updateVerified() {
    if (!currentChart || !candleSeries || !volumeSeries) return showVerified();
    const data = chartData(model.candles);
    candleSeries.setData(data.candles);
    volumeSeries.setData(data.volumes);
    syncIndicators();
    source.textContent = "TradingView ┬╖ " + (model.priceUnit === "usd" ? "USD" : model.market.quoteSymbol)
      + " ┬╖ validated Swap executions";
    ohlc.textContent = model.candles.length
      ? "Last trade " + formatExecution(model.lastTradePrice) + " " +
        (model.priceUnit === "usd" ? "USD" : model.market.quoteSymbol) + " ┬╖ " +
        new Date(model.lastTradeTimestamp * 1000).toLocaleString()
      : "No executed trades in the selected range";
  }  function showIframe(url, label) {
    closeChart();
    panel.replaceChildren();
    const iframe = document.createElement("iframe");
    iframe.className = "terminal-embed";
    iframe.title = label;
    iframe.loading = "eager";
    iframe.allow = "fullscreen";
    iframe.referrerPolicy = "strict-origin-when-cross-origin";
    iframe.src = url;
    panel.append(iframe);
    source.textContent = label + " ┬╖ external DexScreener";
    ohlc.textContent = "Timeframes, drawing tools, and indicators are inside the embedded chart";
  }
  function render() {
    if (disposed || !model) return;
    const hasDex = dexscreenerEmbed(dexscreenerUrl);
    const reference = vettedReference(snapshot?.referenceMarket, snapshot?.market?.pool);
    const safeDefault = selectedDefaultMode(model.health, dexscreenerUrl);
    // An exhausted original pool may only show the broken iframe if the user
    // explicitly clicks Raw DexScreener. Never auto-switch into it.
    selectedMode = requestedMode && modeEnabled(requestedMode) ? requestedMode : safeDefault;
    if (renderedPool && renderedPool !== model.market.pool) {
      closeChart(); requestedMode = null;
      selectedMode = safeDefault;
    }
    renderedPool = model.market.pool;
    if (model.health.status !== "active" && selectedMode === "dex" && requestedMode !== "dex") {
      selectedMode = "verified";
    }
    const unit = model.priceUnit === "usd" ? " USD" : " " + model.market.quoteSymbol;
    pairTitle.textContent = model.market.baseSymbol + "/" + model.market.quoteSymbol;
    const lastText = formatExecution(model.lastTradePrice) + unit;
    const pct = model.change24h === null ? "24h unavailable" :
      "24h " + model.change24h.toFixed(2) + "%";
    stats.textContent = "Last execution " + lastText + "  ΓÇó  " + pct;
    if (model.health.status === "out-of-range") {
      ribbon.className = "terminal-health is-warning";
      ribbon.textContent = "ΓÜá OUT OF RANGE ΓÇö ZERO ACTIVE LIQUIDITY. "
        + "Selected Abyss pool price is not executable. The apparent zero-price DexScreener candle "
        + "reflects a terminal spot tick, not a zero-price swap. ";
      if (selectedMode === "dex") {
        ribbon.textContent += "RAW FEED SELECTED ΓÇö prices may be misleading.";
      }
    } else if (model.health.status === "unknown") {
      ribbon.className = "terminal-health is-warning";
      ribbon.textContent = "Market liquidity could not be verified. Displaying executed trades; "
        + "obtain a fresh on-chain quote before trading.";
    } else {
      ribbon.className = "terminal-health is-ok";
      ribbon.textContent = "Active liquidity detected. DexScreener remains available; "
        + "verified executions can be compared independently. Not a trade quote.";
    }
    if (model.currencyFallback) ribbon.textContent += " Historical USD FX unavailable; charting in quote units.";
    if (selectedMode === "dex" && hasDex) {
      const existing = panel.querySelector("iframe.terminal-embed");
      if (!existing || existing.src !== hasDex) showIframe(hasDex, "Selected Abyss pool on DexScreener");
    } else if (selectedMode === "reference" && reference) {
      const existing = panel.querySelector("iframe.terminal-embed");
      if (!existing || existing.src !== reference.url)
        showIframe(reference.url, "REFERENCE ONLY ΓÇö " + reference.venue + " " + reference.pair);
      ribbon.textContent += " Reference chart is a DIFFERENT pool: " + reference.venue
        + " " + reference.pair + ". It is not the selected Abyss market.";
    } else {
      selectedMode = "verified";
      if (currentChart) updateVerified();
      else showVerified();
    }
    updateControls();
    root.dataset.chartMode = selectedMode;
    root.dataset.poolStatus = model.health.status;
  }
  async function refresh() {
    try {
      const data = await loadSnapshot();
      if (disposed) return;
      snapshot = data;
      model = asTerminalModel(snapshot, currentPeriod);
      render();
    } catch (error) {
      if (disposed) return;
      ribbon.className = "terminal-health is-warning";
      ribbon.textContent = "Market data unavailable ΓÇö not displaying a price. " + String(error?.message ?? "");
      if (!snapshot) { closeChart(); panel.replaceChildren(); }
    }
  }
  async function choosePeriod(period) {
    if (!snapshot || !(period in PERIODS)) return;
    currentPeriod = period;
    model = asTerminalModel(snapshot, currentPeriod);
    if (selectedMode === "verified") closeChart(); // time-axis interval changed
    render();
  }
  function chooseMode(mode) {
    if (!modeEnabled(mode)) return;
    requestedMode = mode;
    render();
  }
  dexBtn.addEventListener("click", () => chooseMode("dex"));
  fillsBtn.addEventListener("click", () => chooseMode("verified"));
  refBtn.addEventListener("click", () => chooseMode("reference"));
  for (const [period, el] of periodButtons) {
    el.addEventListener("click", () => choosePeriod(period));
  }
  for (const [name, el] of indicatorButtons) {
    el.addEventListener("click", () => {
      if (selectedMode !== "verified") return;
      if (activeIndicators.has(name)) activeIndicators.delete(name);
      else activeIndicators.add(name);
      syncIndicators();
      updateControls();
    });
  }
  drawBtn.addEventListener("click", () => { drawing = !drawing; updateControls(); });
  clearBtn.addEventListener("click", () => {
    if (!candleSeries) return;
    for (const level of drawnLevels) candleSeries.removePriceLine(level);
    drawnLevels = [];
  });
  zoomIn.addEventListener("click", () => currentChart?.timeScale().applyOptions({
    barSpacing: Math.min(80, currentChart.timeScale().options().barSpacing * 1.35)
  }));
  zoomOut.addEventListener("click", () => currentChart?.timeScale().applyOptions({
    barSpacing: Math.max(1, currentChart.timeScale().options().barSpacing / 1.35)
  }));
  liveBtn.addEventListener("click", () => currentChart?.timeScale().scrollToRealTime());
  scaleBtn.addEventListener("click", () => {
    logarithmic = !logarithmic;
    currentChart?.priceScale("right", 0).applyOptions({ mode: logarithmic ? 1 : 0 });
    updateControls();
  });
  saveBtn.addEventListener("click", () => {
    if (!currentChart) return;
    const link = document.createElement("a");
    link.download = "abyss-swap-executions.png";
    link.href = currentChart.takeScreenshot().toDataURL("image/png");
    link.click();
  });
  fullBtn.addEventListener("click", () => {
    if (document.fullscreenElement === root) void document.exitFullscreen();
    else if (root.requestFullscreen) void root.requestFullscreen();
  });
  refreshBtn.addEventListener("click", () => { void refresh(); });
  await refresh();
  if (pollMs >= 2000) poll = setInterval(() => { void refresh(); }, pollMs);
  return {
    getSnapshot: () => snapshot, getModel: () => model, getMode: () => selectedMode,
    refresh, chooseMode, choosePeriod,
    dispose: () => {
      if (disposed) return;
      disposed = true;
      if (poll != null) clearInterval(poll);
      closeChart();
      root.remove();
    },
  };
}