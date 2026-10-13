import type { GroupSummary } from "./types";

export const USDC = { symbol: "USDC", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" };
export const USDT = { symbol: "USDT", address: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2" };
export const DAI = { symbol: "DAI", address: "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb" };
export const WETH = { symbol: "WETH", address: "0x4200000000000000000000000000000000000006" };
export const WBTC = { symbol: "WBTC", address: "0x1ceA84203673764244E05693e42E6Ace62bE9BA5" };

/** Placeholder data matching the Figma "First-access introduction" screen until real data wiring lands. */
export const currentAllocation: GroupSummary[] = [
  { id: "stablecoins", name: "Stablecoins", color: "#6366f1", tokens: [USDC, USDT], trailing: { kind: "percentage", value: 0.667 } },
  { id: "crypto-majors", name: "Crypto majors", color: "#a855f7", tokens: [WETH, WBTC], trailing: { kind: "percentage", value: 0.333 } },
];

export const targetAllocation: GroupSummary[] = [
  { id: "stablecoins", name: "Stablecoins", color: "#6366f1", tokens: [USDC, USDT], trailing: { kind: "percentage", value: 0.6 } },
  { id: "crypto-majors", name: "Crypto majors", color: "#a855f7", tokens: [WETH, WBTC], trailing: { kind: "percentage", value: 0.4 } },
];
