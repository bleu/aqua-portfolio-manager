import type { Meta, StoryObj } from "@storybook/react";
import { SetStrategyParametersPage } from "./SetStrategyParametersPage";

const meta: Meta<typeof SetStrategyParametersPage> = {
  title: "Pages/SetStrategyParameters",
  component: SetStrategyParametersPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof SetStrategyParametersPage>;

export const Default: Story = {
  args: {
    network: "Base",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
  },
};
