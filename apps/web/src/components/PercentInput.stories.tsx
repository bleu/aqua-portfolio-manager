import type { Meta, StoryObj } from "@storybook/react";
import { PercentInput } from "./PercentInput";

const meta: Meta<typeof PercentInput> = {
  title: "Primitives/PercentInput",
  component: PercentInput,
  parameters: { layout: "centered" },
};
export default meta;

type Story = StoryObj<typeof PercentInput>;

export const Default: Story = {
  args: { value: 70.1 },
};

export const Disabled: Story = {
  args: { value: 2, disabled: true },
};
