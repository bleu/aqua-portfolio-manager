import type { Meta, StoryObj } from "@storybook/react";
import { Button } from "./Button";

const meta: Meta<typeof Button> = {
  title: "Primitives/Button",
  component: Button,
};
export default meta;

type Story = StoryObj<typeof Button>;

export const Primary: Story = {
  args: { variant: "primary", children: "Set up Portfolio Manager" },
};

export const Secondary: Story = {
  args: { variant: "secondary", children: "Back" },
};

export const Disabled: Story = {
  args: { variant: "primary", children: "Continue to targets", disabled: true },
};
