import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react";
import { SegmentedControl } from "./SegmentedControl";

const meta: Meta<typeof SegmentedControl> = {
  title: "Primitives/SegmentedControl",
  component: SegmentedControl,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof SegmentedControl>;

const RANGES = ["24h", "7d", "30d", "90d", "All"] as const;

export const TimeRange: Story = {
  render: () => {
    function Demo() {
      const [value, setValue] = useState<(typeof RANGES)[number]>("30d");
      return <SegmentedControl options={RANGES} value={value} onChange={setValue} />;
    }
    return <Demo />;
  },
};

export const SingleOptionSelected: Story = {
  args: { options: RANGES, value: "24h", onChange: () => {} },
};
