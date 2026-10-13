import type { Meta, StoryObj } from "@storybook/react";
import { FirstAccessIntroductionPage } from "./FirstAccessIntroductionPage";
import { currentAllocation, targetAllocation } from "@/lib/mockData";

const meta: Meta<typeof FirstAccessIntroductionPage> = {
  title: "Pages/FirstAccessIntroduction",
  component: FirstAccessIntroductionPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof FirstAccessIntroductionPage>;

export const TwoGroupBasket: Story = {
  args: { currentAllocation, targetAllocation },
};

export const SingleGroupBasket: Story = {
  args: {
    currentAllocation: currentAllocation.slice(0, 1),
    targetAllocation: targetAllocation.slice(0, 1),
  },
};
