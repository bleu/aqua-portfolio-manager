import type { Meta, StoryObj } from "@storybook/react";
import { SignatureProgressBar } from "./SignatureProgressBar";

const meta: Meta<typeof SignatureProgressBar> = {
  title: "Primitives/SignatureProgressBar",
  component: SignatureProgressBar,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof SignatureProgressBar>;

export const OneOfThree: Story = {
  args: { total: 3, signed: 1 },
};

export const TwoOfThree: Story = {
  args: { total: 3, signed: 2 },
};
