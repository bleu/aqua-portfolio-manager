import type { Meta, StoryObj } from "@storybook/react";
import { TargetAllocationRow } from "./TargetAllocationRow";

const meta: Meta<typeof TargetAllocationRow> = {
  title: "Composed/TargetAllocationRow",
  component: TargetAllocationRow,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof TargetAllocationRow>;

export const Editable: Story = {
  args: {
    name: "Stablecoins",
    color: "#6366f1",
    tokenSymbols: ["USDC", "USDT", "DAI"],
    currentPct: 70.1,
    currentValue: 10000,
    targetPct: 70.1,
  },
};

export const ReadOnly: Story = {
  args: {
    name: "Crypto majors",
    color: "#a855f7",
    tokenSymbols: ["WETH", "WBTC"],
    currentPct: 29.9,
    currentValue: 4270,
    targetPct: 33.3,
    readOnly: true,
  },
};
