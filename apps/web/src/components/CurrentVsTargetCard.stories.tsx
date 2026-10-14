import type { Meta, StoryObj } from "@storybook/react";
import { CurrentVsTargetCard } from "./CurrentVsTargetCard";

const meta: Meta<typeof CurrentVsTargetCard> = {
  title: "Composed/CurrentVsTargetCard",
  component: CurrentVsTargetCard,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof CurrentVsTargetCard>;

export const TwoBaskets: Story = {
  args: {
    baskets: [
      {
        label: "Crypto majors",
        currentPct: 42,
        targetPct: 33.3,
        caption: "Routing reduces the overweight basket toward 33.3%",
      },
      {
        label: "Stablecoins",
        currentPct: 58,
        targetPct: 66.7,
        caption: "Routing increases the underweight basket toward 66.7%",
      },
    ],
  },
};

export const ThreeBaskets: Story = {
  args: {
    baskets: [
      {
        label: "Crypto majors",
        currentPct: 50,
        targetPct: 40,
        caption: "Routing reduces the overweight basket toward 40%",
      },
      {
        label: "Stablecoins",
        currentPct: 30,
        targetPct: 40,
        caption: "Routing increases the underweight basket toward 40%",
      },
      {
        label: "LSTs",
        currentPct: 20,
        targetPct: 20,
        caption: "Already at target -- no routing needed",
      },
    ],
  },
};
