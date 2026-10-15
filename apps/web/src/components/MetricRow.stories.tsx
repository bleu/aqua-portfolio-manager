import type { Meta, StoryObj } from "@storybook/react";
import { MetricRow } from "./MetricRow";

const meta: Meta<typeof MetricRow> = {
  title: "Primitives/MetricRow",
  component: MetricRow,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof MetricRow>;

export const Large: Story = {
  args: { label: "Total managed value", value: "$15,000.00", caption: "Assets managed by this Portfolio Manager", size: "large" },
};

export const WithDivider: Story = {
  args: { label: "Net LP fees earned", value: "$128.42", caption: "After protocol fee", divider: true },
};
