import type { Meta, StoryObj } from "@storybook/react";
import { WelcomeModal } from "./WelcomeModal";

const meta: Meta<typeof WelcomeModal> = {
  title: "Composed/WelcomeModal",
  component: WelcomeModal,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof WelcomeModal>;

export const Default: Story = {
  args: { onContinue: () => {} },
};
