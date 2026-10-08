import type { Meta, StoryObj } from "@storybook/react";
import { AddressBadge } from "./AddressBadge";

const meta: Meta<typeof AddressBadge> = {
  title: "Composed/AddressBadge",
  component: AddressBadge,
};
export default meta;

type Story = StoryObj<typeof AddressBadge>;

export const SafeWallet: Story = {
  args: { label: "Safe", address: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B" },
};

export const EoaWallet: Story = {
  args: { label: "Wallet", address: "0x1234567890abcdef1234567890abcdef12345678" },
};
