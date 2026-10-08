import { DAI, USDC, USDT, WBTC, WETH } from "./mockData";
import type { Token } from "./types";

export type BasketDraft = {
  id: string;
  name: string;
  color: string;
  tokenAddresses: string[];
};

export type SafeToken = Token & {
  balance: number;
  value: number;
};

/** Every token the connected Safe holds, with its real on-chain balance and oracle-valued USD amount. */
export const safeTokens: SafeToken[] = [
  { ...USDC, balance: 6200, value: 6200 },
  { ...USDT, balance: 2100, value: 2100 },
  { ...DAI, balance: 1700, value: 1700 },
  { ...WETH, balance: 1.52, value: 4270 },
  { ...WBTC, balance: 0, value: 0 },
];

export const initialBaskets: BasketDraft[] = [
  { id: "stablecoins", name: "Stablecoins", color: "#6366f1", tokenAddresses: [USDC.address, USDT.address, DAI.address] },
  { id: "crypto-majors", name: "Crypto majors", color: "#a855f7", tokenAddresses: [WETH.address, WBTC.address] },
];
