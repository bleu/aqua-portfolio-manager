import type { Meta, StoryObj } from "@storybook/react";
import { WaitingForSafeSignaturesPage } from "./WaitingForSafeSignaturesPage";

const meta: Meta<typeof WaitingForSafeSignaturesPage> = {
  title: "Pages/WaitingForSafeSignatures",
  component: WaitingForSafeSignaturesPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof WaitingForSafeSignaturesPage>;

const baskets = [
  { id: "stablecoins", name: "Stablecoins", tokenSymbols: ["USDC", "USDT", "DAI"], currentPct: 50, currentValue: 5000, targetPct: 35 },
  { id: "majors", name: "Majors", tokenSymbols: ["BTC", "ETH"], currentPct: 50, currentValue: 5000, targetPct: 65 },
];

export const Signing: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    signaturesRequired: 3,
    signaturesCollected: 1,
    transactionHash: "0x8A2F0000000000000000000000000000000000000000000000000000000030C1",
    priceDeviationPct: 5,
    lpFeePct: 2,
    baskets,
  },
};

export const ReadyToExecute: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    signaturesRequired: 3,
    signaturesCollected: 3,
    transactionHash: "0x8A2F0000000000000000000000000000000000000000000000000000000030C1",
    priceDeviationPct: 5,
    lpFeePct: 2,
    baskets,
  },
};
