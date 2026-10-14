import type { Meta, StoryObj } from "@storybook/react";
import { Badge } from "./Badge";

const meta: Meta<typeof Badge> = {
  title: "Primitives/Badge",
  component: Badge,
  parameters: { layout: "centered" },
};
export default meta;

type Story = StoryObj<typeof Badge>;

export const Plain: Story = {
  args: { children: "Ethereum" },
};

export const PlainWithDot: Story = {
  args: { children: "Ethereum", dotColor: "#22c55e" },
};

export const Outline: Story = {
  args: { variant: "outline", children: "Safe smart account required" },
};

export const Dot: Story = {
  args: { variant: "dot", children: "Aqua routing" },
};
