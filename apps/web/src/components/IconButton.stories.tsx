import type { Meta, StoryObj } from "@storybook/react";
import { IconButton } from "./IconButton";
import { MoreIcon } from "./icons";

const meta: Meta<typeof IconButton> = {
  title: "Primitives/IconButton",
  component: IconButton,
  parameters: { layout: "centered" },
};
export default meta;

type Story = StoryObj<typeof IconButton>;

export const Default: Story = {
  args: { "aria-label": "More options", children: <MoreIcon className="size-4" /> },
};

export const Disabled: Story = {
  args: { "aria-label": "More options", children: <MoreIcon className="size-4" />, disabled: true },
};
