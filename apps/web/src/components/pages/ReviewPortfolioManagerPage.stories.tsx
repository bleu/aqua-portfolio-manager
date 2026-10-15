import type { Meta, StoryObj } from "@storybook/react";
import { ReviewPortfolioManagerPage } from "./ReviewPortfolioManagerPage";

const meta: Meta<typeof ReviewPortfolioManagerPage> = {
  title: "Pages/ReviewPortfolioManager",
  component: ReviewPortfolioManagerPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof ReviewPortfolioManagerPage>;

const baskets = [
  {
    id: "stablecoins",
    name: "Stablecoins",
    color: "#6366f1",
    tokenSymbols: ["USDC", "USDT", "DAI"],
    currentPct: 66.7,
    currentValue: 10000,
    targetPct: 66.7,
  },
  {
    id: "crypto-majors",
    name: "Crypto majors",
    color: "#a855f7",
    tokenSymbols: ["WETH", "WBTC", "wstETH"],
    currentPct: 33.3,
    currentValue: 5000,
    targetPct: 33.3,
  },
];

export const NoRebalanceNeeded: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets,
    priceDeviationPct: 1,
    lpFeePct: 2,
    signaturesRequired: 3,
  },
};

export const RebalanceExpected: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets: [
      { ...baskets[0], targetPct: 50 },
      { ...baskets[1], targetPct: 50 },
    ],
    priceDeviationPct: 1,
    lpFeePct: 2,
    signaturesRequired: 2,
  },
};
