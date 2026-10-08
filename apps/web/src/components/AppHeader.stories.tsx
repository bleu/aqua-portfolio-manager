import type { Meta, StoryObj } from "@storybook/react";
import { AppHeader } from "./AppHeader";

const meta: Meta<typeof AppHeader> = {
  title: "Composed/AppHeader",
  component: AppHeader,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof AppHeader>;

export const PortfolioManagerTab: Story = {
  args: {
    tabs: [{ label: "Portfolio Manager", active: true }, { label: "History" }],
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
  },
};

export const HistoryTab: Story = {
  args: {
    tabs: [{ label: "Portfolio Manager" }, { label: "History", active: true }],
    network: "Base",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
  },
};
