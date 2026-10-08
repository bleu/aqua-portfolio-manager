import type { Meta, StoryObj } from "@storybook/react";
import { InfoBanner } from "./InfoBanner";

const meta: Meta<typeof InfoBanner> = {
  title: "Composed/InfoBanner",
  component: InfoBanner,
};
export default meta;

type Story = StoryObj<typeof InfoBanner>;

export const ShortText: Story = {
  args: { children: "Routed trades move allocation toward them while your portfolio earns LP fees." },
};

export const LongText: Story = {
  args: {
    children:
      "Each token can only belong to one basket. Removing a token from a basket makes it available to add to a different one.",
  },
};
