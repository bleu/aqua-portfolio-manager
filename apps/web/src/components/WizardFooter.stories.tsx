import type { Meta, StoryObj } from "@storybook/react";
import { WizardFooter } from "./WizardFooter";

const meta: Meta<typeof WizardFooter> = {
  title: "Composed/WizardFooter",
  component: WizardFooter,
};
export default meta;

type Story = StoryObj<typeof WizardFooter>;

export const BasketsStep: Story = {
  args: { summary: "2 baskets · 5 managed tokens", continueLabel: "Continue to targets", showBack: true },
};

export const FirstStepNoBack: Story = {
  args: { summary: "0 baskets · 0 managed tokens", continueLabel: "Continue to targets", showBack: false, continueDisabled: true },
};
