import type { Meta, StoryObj } from "@storybook/react";
import { Button } from "./Button";
import { EmptyState } from "./EmptyState";

function TargetIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
      <circle cx="10" cy="10" r="7" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="10" cy="10" r="2.5" fill="currentColor" />
    </svg>
  );
}

const meta: Meta<typeof EmptyState> = {
  title: "Composed/EmptyState",
  component: EmptyState,
};
export default meta;

type Story = StoryObj<typeof EmptyState>;

export const WithIconAndAction: Story = {
  args: {
    icon: <TargetIcon />,
    heading: "Set up your Portfolio Manager",
    description:
      "Choose tokens, set group targets, and define price protection. Once active, routed trades help maintain the allocation while your portfolio earns LP fees.",
    action: <Button>Start setup</Button>,
  },
};

export const WithoutIcon: Story = {
  args: {
    heading: "No activity yet",
    description: "Trades will appear here once your strategy starts rebalancing.",
  },
};
