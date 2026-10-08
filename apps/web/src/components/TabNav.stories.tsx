import type { Meta, StoryObj } from "@storybook/react";
import { TabNav } from "./TabNav";

const meta: Meta<typeof TabNav> = {
  title: "Composed/TabNav",
  component: TabNav,
};
export default meta;

type Story = StoryObj<typeof TabNav>;

export const PortfolioManagerActive: Story = {
  args: {
    tabs: [
      { label: "Portfolio Manager", active: true },
      { label: "History" },
    ],
  },
};

export const HistoryActive: Story = {
  args: {
    tabs: [{ label: "Portfolio Manager" }, { label: "History", active: true }],
  },
};
