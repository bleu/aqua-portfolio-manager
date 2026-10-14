import type { Meta, StoryObj } from "@storybook/react";
import { ChoicePillGroup } from "./ChoicePillGroup";

const meta: Meta<typeof ChoicePillGroup> = {
  title: "Composed/ChoicePillGroup",
  component: ChoicePillGroup,
  parameters: { layout: "padded" },
};
export default meta;

type Story = StoryObj<typeof ChoicePillGroup>;

export const Unselected: Story = {
  args: { options: [0.1, 0.5, 1, 2, 5], value: undefined },
};

export const PresetSelected: Story = {
  args: { options: [0.05, 0.3, 1, 2], value: 2 },
};
