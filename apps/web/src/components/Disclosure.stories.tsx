import type { Meta, StoryObj } from "@storybook/react";
import { Disclosure } from "./Disclosure";

const meta: Meta<typeof Disclosure> = {
  title: "Primitives/Disclosure",
  component: Disclosure,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof Disclosure>;

export const Collapsed: Story = {
  args: {
    label: "How price protection works",
    children: "If the quoted price moves beyond this limit compared to the oracle price, the trade waits.",
  },
};

export const Expanded: Story = {
  args: {
    label: "View protocol fee calculation",
    children: "The protocol fee is deducted from the LP fee before earnings reach your Safe.",
    defaultOpen: true,
  },
};
