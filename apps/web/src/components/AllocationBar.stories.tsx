import type { Meta, StoryObj } from "@storybook/react";
import { AllocationBar } from "./AllocationBar";

const meta: Meta<typeof AllocationBar> = {
  title: "Composed/AllocationBar",
  component: AllocationBar,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof AllocationBar>;

export const Overweight: Story = {
  args: {
    label: "Crypto majors",
    currentPct: 42,
    targetPct: 33.3,
    caption: "Routing reduces the overweight basket toward 33.3%",
  },
};

export const Underweight: Story = {
  args: {
    label: "Stablecoins",
    currentPct: 58,
    targetPct: 66.7,
    caption: "Routing increases the underweight basket toward 66.7%",
  },
};

export const OnTarget: Story = {
  args: {
    label: "Balanced basket",
    currentPct: 50,
    targetPct: 50,
    caption: "Already at target -- no routing needed",
  },
};
