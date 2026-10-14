import type { Meta, StoryObj } from "@storybook/react";
import { WizardStepper } from "./WizardStepper";

const steps = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];

const meta: Meta<typeof WizardStepper> = {
  title: "Composed/WizardStepper",
  component: WizardStepper,
};
export default meta;

type Story = StoryObj<typeof WizardStepper>;

export const FirstStep: Story = {
  args: { steps, activeIndex: 0 },
};

export const ThirdStep: Story = {
  args: { steps, activeIndex: 2 },
};
