import type { Meta, StoryObj } from "@storybook/react";
import { GroupSummaryCard } from "./GroupSummaryCard";
import type { GroupSummary } from "@/lib/types";

const usdc = { symbol: "USDC", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" };
const usdt = { symbol: "USDT", address: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2" };
const weth = { symbol: "WETH", address: "0x4200000000000000000000000000000000000006" };

const stablecoinsTarget: GroupSummary = {
  id: "stablecoins",
  name: "Stablecoins",
  color: "#6366f1",
  tokens: [usdc, usdt],
  trailing: { kind: "percentage", value: 0.6 },
};

const cryptoMajorsBasket: GroupSummary = {
  id: "crypto-majors",
  name: "Crypto majors",
  color: "#a855f7",
  tokens: [weth],
  trailing: { kind: "amount", value: 4270 },
  selected: true,
};

const meta: Meta<typeof GroupSummaryCard> = {
  title: "Composed/GroupSummaryCard",
  component: GroupSummaryCard,
};
export default meta;

type Story = StoryObj<typeof GroupSummaryCard>;

export const PercentageWithProgress: Story = {
  args: { group: stablecoinsTarget, showProgress: true },
};

export const AmountSelectedCompact: Story = {
  args: { group: cryptoMajorsBasket, compact: true, onClick: () => {} },
};
