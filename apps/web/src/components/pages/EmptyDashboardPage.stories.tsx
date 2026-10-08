import type { Meta, StoryObj } from "@storybook/react";
import { EmptyDashboardPage } from "./EmptyDashboardPage";

const meta: Meta<typeof EmptyDashboardPage> = {
  title: "Pages/EmptyDashboard",
  component: EmptyDashboardPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof EmptyDashboardPage>;

export const Ethereum: Story = {
  args: { network: "Ethereum", safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B" },
};

export const Base: Story = {
  args: { network: "Base", safeAddress: "0x1234567890abcdef1234567890abcdef12345678" },
};
