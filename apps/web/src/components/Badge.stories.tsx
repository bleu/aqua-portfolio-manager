import type { Meta, StoryObj } from "@storybook/react";
import { Badge } from "./Badge";

const meta: Meta<typeof Badge> = {
  title: "Primitives/Badge",
  component: Badge,
};
export default meta;

type Story = StoryObj<typeof Badge>;

export const PlainText: Story = {
  args: { children: "Safe · 0x71A4...9F2C" },
};

export const WithStatusDot: Story = {
  args: { children: "Ethereum", dotColor: "#22c55e" },
};
