import type { Meta, StoryObj } from "@storybook/react";
import { DetailRow } from "./DetailRow";

const meta: Meta<typeof DetailRow> = {
  title: "Primitives/DetailRow",
  component: DetailRow,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof DetailRow>;

export const Address: Story = {
  args: { label: "Safe", value: "0x71A4...9F2C" },
};

export const Percentage: Story = {
  args: { label: "Price deviation", value: "1%" },
};
