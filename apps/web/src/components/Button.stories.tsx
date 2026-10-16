import type { Meta, StoryObj } from "@storybook/react";
import { Button } from "./Button";

const meta: Meta<typeof Button> = {
  title: "Primitives/Button",
  component: Button,
  parameters: { layout: "centered" },
};
export default meta;

type Story = StoryObj<typeof Button>;

export const Primary: Story = {
  args: { variant: "primary", children: "Connect Safe" },
};

export const Secondary: Story = {
  args: { variant: "secondary", children: "Cancel" },
};

export const Disabled: Story = {
  args: { variant: "primary", children: "Connect Safe", disabled: true },
};

export const Accent: Story = {
  args: { variant: "accent", children: "Create transaction" },
};
