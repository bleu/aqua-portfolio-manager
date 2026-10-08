import type { Meta, StoryObj } from "@storybook/react";
import { RoutedTradesConnector } from "./RoutedTradesConnector";

const meta: Meta<typeof RoutedTradesConnector> = {
  title: "Composed/RoutedTradesConnector",
  component: RoutedTradesConnector,
};
export default meta;

type Story = StoryObj<typeof RoutedTradesConnector>;

export const Default: Story = {
  args: {},
};

export const CustomCaption: Story = {
  args: { caption: "via Pathfinder" },
};
