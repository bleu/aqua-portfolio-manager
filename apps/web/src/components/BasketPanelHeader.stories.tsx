import type { Meta, StoryObj } from "@storybook/react";
import { BasketPanelHeader } from "./BasketPanelHeader";

const meta: Meta<typeof BasketPanelHeader> = {
  title: "Composed/BasketPanelHeader",
  component: BasketPanelHeader,
};
export default meta;

type Story = StoryObj<typeof BasketPanelHeader>;

export const Stablecoins: Story = {
  args: { name: "Stablecoins", color: "#6366f1", tokenCount: 3, totalValue: 10_000 },
};

export const SingleToken: Story = {
  args: { name: "Crypto majors", color: "#a855f7", tokenCount: 1, totalValue: 4270 },
};
