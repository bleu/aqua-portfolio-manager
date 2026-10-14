import type { Meta, StoryObj } from "@storybook/react";
import { WaitingForSafeSignaturesPage } from "./WaitingForSafeSignaturesPage";

const meta: Meta<typeof WaitingForSafeSignaturesPage> = {
  title: "Pages/WaitingForSafeSignatures",
  component: WaitingForSafeSignaturesPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof WaitingForSafeSignaturesPage>;

export const OneOfThree: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    signaturesRequired: 3,
    signaturesCollected: 1,
    transactionHash: "0x8A2F0000000000000000000000000000000000000000000000000000000030C1",
    submittedAt: "Just now",
    priceDeviationPct: 1,
  },
};

export const LastSignerPending: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    signaturesRequired: 3,
    signaturesCollected: 2,
    transactionHash: "0x8A2F0000000000000000000000000000000000000000000000000000000030C1",
    submittedAt: "2 minutes ago",
    priceDeviationPct: 1,
  },
};
