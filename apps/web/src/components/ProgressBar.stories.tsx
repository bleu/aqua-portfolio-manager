import type { Meta, StoryObj } from "@storybook/react";
import { ProgressBar } from "./ProgressBar";

const meta: Meta<typeof ProgressBar> = {
  title: "Primitives/ProgressBar",
  component: ProgressBar,
};
export default meta;

type Story = StoryObj<typeof ProgressBar>;

export const PartiallyFilled: Story = {
  args: { value: 0.6 },
};

export const NearlyFull: Story = {
  args: { value: 0.95 },
};
