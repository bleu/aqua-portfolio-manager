import type { Meta, StoryObj } from "@storybook/react";
import { getBasketColor } from "@/lib/basketColors";
import { ActivePortfolioManagerDashboardPage } from "./ActivePortfolioManagerDashboardPage";

const meta: Meta<typeof ActivePortfolioManagerDashboardPage> = {
  title: "Pages/ActivePortfolioManagerDashboard",
  component: ActivePortfolioManagerDashboardPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof ActivePortfolioManagerDashboardPage>;

const dates = ["Aug 25", "Sep 1", "Sep 8", "Sep 15", "Sep 24"];

const baskets = [
  {
    id: "stablecoins",
    name: "Stablecoins",
    color: getBasketColor(0).solid,
    managedValue: 10000,
    currentPct: 66.7,
    targetPct: 66.7,
    tokens: [
      { symbol: "USDC", name: "USD Coin", address: "0x8335...2913", balance: 4500, value: 4500 },
      { symbol: "USDT", name: "Tether USD", address: "0xfde4...9bb2", balance: 3500, value: 3500 },
      { symbol: "DAI", name: "Dai", address: "0x50c5...B0Cb", balance: 2000, value: 2000 },
    ],
  },
  {
    id: "crypto-majors",
    name: "Crypto majors",
    color: getBasketColor(1).solid,
    managedValue: 5000,
    currentPct: 33.3,
    targetPct: 33.3,
    tokens: [
      { symbol: "WETH", name: "Wrapped Ether", address: "0x4200...0006", balance: 1.2, value: 3000 },
      { symbol: "WBTC", name: "Wrapped Bitcoin", address: "0x0555...d2B9c", balance: 0.02, value: 1800 },
      { symbol: "wstETH", name: "Wrapped stETH", address: "0x7f39...0298", balance: 0.07, value: 200 },
    ],
  },
];

const chartSeries = [
  {
    id: "stablecoins",
    name: "Stablecoins current",
    color: getBasketColor(0).solid,
    targetPct: 66.7,
    points: [68, 65, 67, 69, 66.7].map((pct, i) => ({ date: dates[i]!, pct })),
  },
  {
    id: "crypto-majors",
    name: "Crypto majors current",
    color: getBasketColor(1).solid,
    targetPct: 33.3,
    points: [32, 35, 33, 31, 33.3].map((pct, i) => ({ date: dates[i]!, pct })),
  },
];

const volumeSeries = Array.from({ length: 30 }, (_, i) => ({
  date: `Day ${i + 1}`,
  value: 800 + Math.round(Math.sin(i / 3) * 500 + (i % 7) * 120),
}));

const targetsRecap = [
  { id: "stablecoins", name: "Stablecoins", tokenSymbols: ["USDC", "USDT", "DAI"], targetPct: 66.7 },
  { id: "crypto-majors", name: "Crypto majors", tokenSymbols: ["WETH", "WBTC", "wstETH"], targetPct: 33.3 },
];

export const TwoBaskets: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    updatedAt: Date.now() - 12_000,
    managedValue: 15000,
    netLpFeesEarned: 128.42,
    routedVolume: 42830,
    routedTransactionCount: 24,
    baskets,
    chartSeries,
    volumeSeries,
    priceDeviationPct: 1,
    lpFeePct: 2,
    targetsRecap,
    onUpdateStrategy: () => {},
  },
};

export const RecentlyUpdated: Story = {
  args: {
    network: "Base",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    updatedAt: Date.now() - 2_000,
    managedValue: 42000,
    netLpFeesEarned: 310.1,
    routedVolume: 98000,
    routedTransactionCount: 51,
    baskets,
    chartSeries,
    volumeSeries,
    priceDeviationPct: 1,
    lpFeePct: 2,
    targetsRecap,
  },
};

/** No volumeSeries passed -- the Volume tab's honest empty state (Dashboard_Empty.dc.html), since
 *  nothing in this app reads historical routed-volume data yet. */
export const NoActivityYet: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    updatedAt: Date.now() - 12_000,
    managedValue: 15000,
    netLpFeesEarned: 0,
    routedVolume: 0,
    routedTransactionCount: 0,
    baskets,
    chartSeries,
    priceDeviationPct: 1,
    lpFeePct: 2,
    targetsRecap,
  },
};

/** Matches Dashboard_Paused.dc.html -- automatic rebalancing stopped because one basket's price
 *  deviation exceeded the configured limit, confirmed in Round 1's own doc comment on `status`. */
export const Paused: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    updatedAt: Date.now() - 12_000,
    managedValue: 15000,
    netLpFeesEarned: 128.42,
    routedVolume: 42830,
    routedTransactionCount: 24,
    baskets,
    chartSeries,
    volumeSeries,
    priceDeviationPct: 1,
    lpFeePct: 2,
    targetsRecap,
    status: "paused",
    pausedAlert: {
      affectedBasketName: "Crypto majors",
      priceDeviationPct: 6.4,
      yourLimitPct: 5,
    },
  },
};
