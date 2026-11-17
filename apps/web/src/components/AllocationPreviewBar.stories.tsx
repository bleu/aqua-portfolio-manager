import type { Meta, StoryObj } from "@storybook/react";
import { getBasketColor } from "@/lib/basketColors";
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
      { id: "stablecoins", name: "Stablecoins", color: getBasketColor(0).solid, targetPct: 70.1 },
      { id: "crypto-majors", name: "Crypto majors", color: getBasketColor(1).solid, targetPct: 29.9 },
    ],
  },
};

export const FourBaskets: Story = {
  args: {
    baskets: [
      { id: "a", name: "Stablecoins", color: getBasketColor(0).solid, targetPct: 40 },
      { id: "b", name: "Crypto majors", color: getBasketColor(1).solid, targetPct: 30 },
      { id: "c", name: "DeFi", color: getBasketColor(2).solid, targetPct: 20 },
      { id: "d", name: "Memecoins", color: getBasketColor(3).solid, targetPct: 10 },
    ],
  },
};
