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

const network = "Base";
const safeAddress = "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B";

export const TwoGroupBasket: Story = {
  args: { network, safeAddress, currentAllocation, targetAllocation },
};

export const SingleGroupBasket: Story = {
  args: {
    network,
    safeAddress,
    currentAllocation: currentAllocation.slice(0, 1),
    targetAllocation: targetAllocation.slice(0, 1),
  },
};
