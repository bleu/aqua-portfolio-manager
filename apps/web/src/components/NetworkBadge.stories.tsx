import type { Meta, StoryObj } from "@storybook/react";
import { NetworkBadge } from "./NetworkBadge";

const meta: Meta<typeof NetworkBadge> = {
  title: "Composed/NetworkBadge",
  component: NetworkBadge,
};
export default meta;

type Story = StoryObj<typeof NetworkBadge>;

export const Ethereum: Story = {
  args: { network: "Ethereum" },
};

export const Base: Story = {
  args: { network: "Base", statusColor: "#2563eb" },
};
