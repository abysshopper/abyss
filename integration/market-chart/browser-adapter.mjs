import { mountAbyssTerminal } from "./trading-terminal.mjs";
/** Backward-friendly entry point: installs the hybrid DexScreener/TradingView
 * terminal in the provided container. Returns the terminal controller.
 */
export async function refreshAbyssChart(host, loadSnapshot, options = {}) {
  return mountAbyssTerminal(host, { loadSnapshot, ...options });
}