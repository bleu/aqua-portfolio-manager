import type { Meta, StoryObj } from "@storybook/react";
import { AddBasketButton } from "./AddBasketButton";

const meta: Meta<typeof AddBasketButton> = {
  title: "Composed/AddBasketButton",
  component: AddBasketButton,
};
export default meta;

type Story = StoryObj<typeof AddBasketButton>;

export const Default: Story = {
  args: {},
};

export const InNarrowColumn: Story = {
  args: {},
  decorators: [(Story) => <div style={{ width: 240 }}><Story /></div>],
};
