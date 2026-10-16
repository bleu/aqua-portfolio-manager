import type { Meta, StoryObj } from "@storybook/react";
import { StatColumn } from "./StatColumn";

const meta: Meta<typeof StatColumn> = {
  title: "Primitives/StatColumn",
  component: StatColumn,
  parameters: { layout: "centered" },
};
export default meta;

type Story = StoryObj<typeof StatColumn>;

export const Currency: Story = {
  args: { value: "$15,000", label: "Managed value" },
};

export const Count: Story = {
  args: { value: "2", label: "Baskets" },
};
