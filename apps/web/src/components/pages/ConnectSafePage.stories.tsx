import type { Meta, StoryObj } from "@storybook/react";
import { ConnectSafePage } from "./ConnectSafePage";

const meta: Meta<typeof ConnectSafePage> = {
  title: "Pages/ConnectSafePage",
  component: ConnectSafePage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof ConnectSafePage>;

export const Default: Story = {};

export const Connecting: Story = {
  args: { isConnecting: true },
};

export const Error: Story = {
  args: { connectError: "Provider not found. Version: @wagmi/core@3.6.5" },
};
