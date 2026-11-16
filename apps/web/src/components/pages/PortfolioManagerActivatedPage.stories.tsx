import type { Meta, StoryObj } from "@storybook/react";
import { getBasketColor } from "@/lib/basketColors";
import { PortfolioManagerActivatedPage } from "./PortfolioManagerActivatedPage";

const meta: Meta<typeof PortfolioManagerActivatedPage> = {
  title: "Pages/PortfolioManagerActivated",
  component: PortfolioManagerActivatedPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof PortfolioManagerActivatedPage>;

export const TwoBaskets: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    managedValue: 15000,
    baskets: [
      { id: "stablecoins", name: "Stablecoins", color: getBasketColor(0).solid, tokenSymbols: ["USDC", "USDT", "DAI"], currentPct: 66.7 },
      { id: "crypto-majors", name: "Crypto majors", color: getBasketColor(1).solid, tokenSymbols: ["WETH", "WBTC", "wstETH"], currentPct: 33.3 },
    ],
    tokenCount: 6,
    lpFeePct: 2,
    activationTxHash: "0x8A2F0000000000000000000000000000000000000000000000000000000030C1",
  },
};

export const FourBaskets: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    managedValue: 42000,
    baskets: [
      { id: "a", name: "Stablecoins", color: getBasketColor(0).solid, tokenSymbols: ["USDC", "USDT"], currentPct: 40 },
      { id: "b", name: "Crypto majors", color: getBasketColor(1).solid, tokenSymbols: ["WETH", "WBTC"], currentPct: 30 },
      { id: "c", name: "DeFi", color: getBasketColor(2).solid, tokenSymbols: ["AAVE", "LINK"], currentPct: 20 },
      { id: "d", name: "Memecoins", color: getBasketColor(3).solid, tokenSymbols: ["DEGEN"], currentPct: 10 },
    ],
    tokenCount: 7,
    lpFeePct: 1,
    activationTxHash: "0x8A2F0000000000000000000000000000000000000000000000000000000030C1",
  },
};
