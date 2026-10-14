import type { Meta, StoryObj } from "@storybook/react";
import { AllocationPreviewBar } from "./AllocationPreviewBar";

const meta: Meta<typeof AllocationPreviewBar> = {
  title: "Composed/AllocationPreviewBar",
  component: AllocationPreviewBar,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof AllocationPreviewBar>;

export const TwoBaskets: Story = {
  args: {
    baskets: [
      { id: "stablecoins", name: "Stablecoins", color: "#6366f1", targetPct: 70.1 },
      { id: "crypto-majors", name: "Crypto majors", color: "#a855f7", targetPct: 29.9 },
    ],
  },
};

export const FourBaskets: Story = {
  args: {
    baskets: [
      { id: "a", name: "Stablecoins", color: "#6366f1", targetPct: 40 },
      { id: "b", name: "Crypto majors", color: "#a855f7", targetPct: 30 },
      { id: "c", name: "DeFi", color: "#22c55e", targetPct: 20 },
      { id: "d", name: "Memecoins", color: "#f59e0b", targetPct: 10 },
    ],
  },
};
