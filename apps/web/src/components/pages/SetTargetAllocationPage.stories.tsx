import type { Meta, StoryObj } from "@storybook/react";
import { SetTargetAllocationPage } from "./SetTargetAllocationPage";

const meta: Meta<typeof SetTargetAllocationPage> = {
  title: "Pages/SetTargetAllocation",
  component: SetTargetAllocationPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof SetTargetAllocationPage>;

const twoBaskets = [
  { id: "stablecoins", name: "Stablecoins", color: "#6366f1", tokenSymbols: ["USDC", "USDT", "DAI"], currentValue: 10000 },
  { id: "crypto-majors", name: "Crypto majors", color: "#a855f7", tokenSymbols: ["WETH", "WBTC"], currentValue: 4270 },
];

export const TwoBaskets: Story = {
  args: {
    network: "Base",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets: twoBaskets,
  },
};

export const FourBaskets: Story = {
  args: {
    network: "Base",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets: [
      ...twoBaskets,
      { id: "defi", name: "DeFi", color: "#22c55e", tokenSymbols: ["AAVE", "LINK"], currentValue: 2000 },
      { id: "memecoins", name: "Memecoins", color: "#f59e0b", tokenSymbols: ["DEGEN"], currentValue: 500 },
    ],
  },
};
