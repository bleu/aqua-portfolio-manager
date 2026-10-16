import type { Meta, StoryObj } from "@storybook/react";
import { AllocationHistoryChart } from "./AllocationHistoryChart";

const meta: Meta<typeof AllocationHistoryChart> = {
  title: "Composed/AllocationHistoryChart",
  component: AllocationHistoryChart,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof AllocationHistoryChart>;

const dates = ["Aug 25", "Sep 1", "Sep 8", "Sep 15", "Sep 24"];

export const TwoBaskets: Story = {
  args: {
    series: [
      {
        id: "stablecoins",
        name: "Stablecoins current",
        color: "#6366f1",
        targetPct: 66.7,
        points: [68, 65, 67, 69, 66.7].map((pct, i) => ({ date: dates[i], pct })),
      },
      {
        id: "crypto-majors",
        name: "Crypto majors current",
        color: "#22c55e",
        targetPct: 33.3,
        points: [32, 35, 33, 31, 33.3].map((pct, i) => ({ date: dates[i], pct })),
      },
    ],
  },
};

export const SingleBasket: Story = {
  args: {
    series: [
      {
        id: "stablecoins",
        name: "Stablecoins current",
        color: "#6366f1",
        targetPct: 100,
        points: [100, 100, 100, 100, 100].map((pct, i) => ({ date: dates[i], pct })),
      },
    ],
  },
};
