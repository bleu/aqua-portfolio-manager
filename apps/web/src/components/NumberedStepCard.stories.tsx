import type { Meta, StoryObj } from "@storybook/react";
import { NumberedStepCard } from "./NumberedStepCard";

const meta: Meta<typeof NumberedStepCard> = {
  title: "Composed/NumberedStepCard",
  component: NumberedStepCard,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof NumberedStepCard>;

export const WithBody: Story = {
  args: {
    index: 1,
    title: "Set the price deviation limit",
    subtitle: "Choose the maximum difference allowed between the quoted price and the oracle price.",
    children: <p className="text-sm text-gray-400">Choice controls render here.</p>,
  },
};

export const TitleOnly: Story = {
  args: {
    index: 2,
    title: "LP fees accumulate",
    subtitle: "Your dashboard shows the net LP fees earned after the protocol fee.",
  },
};
