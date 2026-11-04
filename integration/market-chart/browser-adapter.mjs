import { marketChartModel, renderMarketChart } from "./market-chart.mjs";
/** Replace the embedded chart with canonical executed-swap candles.
 * Input is a reorg-aware indexer snapshot plus fresh pool liquidity state.
 * Neither this adapter nor the candle data are executable quotes.
 */
export async function refreshAbyssChart(container, loadSnapshot, options = {}) {
  if (!container || typeof loadSnapshot !== "function") {
    throw new TypeError("Expected chart container and asynchronous snapshot loader");
  }
  const snapshot = await loadSnapshot();
  const model = marketChartModel(snapshot);
  container.innerHTML = renderMarketChart(model, options);
  container.dataset.abyssChartStatus = model.health.status;
  return model;
}