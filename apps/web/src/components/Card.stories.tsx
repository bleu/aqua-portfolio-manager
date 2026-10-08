import type { Meta, StoryObj } from "@storybook/react";
import { Card } from "./Card";

const meta: Meta<typeof Card> = {
  title: "Primitives/Card",
  component: Card,
};
export default meta;

type Story = StoryObj<typeof Card>;

export const Default: Story = {
  args: {
    children: "Default padding card content.",
  },
};

export const Compact: Story = {
  args: {
    padding: "compact",
    children: "Compact padding card content.",
  },
};
