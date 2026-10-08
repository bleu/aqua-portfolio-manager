import type { Meta, StoryObj } from "@storybook/react";
import { TokenListRow } from "./TokenListRow";

const usdc = { symbol: "USDC", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" };
const weth = { symbol: "WETH", address: "0x4200000000000000000000000000000000000006" };

const meta: Meta<typeof TokenListRow> = {
  title: "Composed/TokenListRow",
  component: TokenListRow,
};
export default meta;

type Story = StoryObj<typeof TokenListRow>;

export const Added: Story = {
  args: { token: usdc, balance: 6200, value: 6200, added: true },
};

export const HighlightedNotYetAdded: Story = {
  args: { token: weth, balance: 1.52, value: 4270, highlighted: true },
};
