import type { Meta, StoryObj } from "@storybook/react";
import { BasketPanelHeader } from "./BasketPanelHeader";

const meta: Meta<typeof BasketPanelHeader> = {
  title: "Composed/BasketPanelHeader",
  component: BasketPanelHeader,
};
export default meta;

type Story = StoryObj<typeof BasketPanelHeader>;

export const Stablecoins: Story = {
  args: { name: "Stablecoins" },
};

export const SingleToken: Story = {
  args: { name: "Crypto majors" },
};
