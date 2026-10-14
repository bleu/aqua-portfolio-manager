import type { Meta, StoryObj } from "@storybook/react";
import { Header } from "./Header";

const meta: Meta<typeof Header> = {
  title: "Primitives/Header",
  component: Header,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof Header>;

export const Default: Story = {};
