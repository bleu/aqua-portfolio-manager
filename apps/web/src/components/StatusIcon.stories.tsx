import type { Meta, StoryObj } from "@storybook/react";
import { StatusIcon } from "./StatusIcon";

const meta: Meta<typeof StatusIcon> = {
  title: "Primitives/StatusIcon",
  component: StatusIcon,
  parameters: { layout: "centered" },
};
export default meta;

type Story = StoryObj<typeof StatusIcon>;

export const Pending: Story = {
  args: { variant: "pending" },
};

export const Success: Story = {
  args: { variant: "success" },
};

export const Error: Story = {
  args: { variant: "error" },
};
