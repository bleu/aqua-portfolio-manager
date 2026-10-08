import type { Meta, StoryObj } from "@storybook/react";
import { TokenChip } from "./TokenChip";

const usdc = { symbol: "USDC", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" };
const weth = { symbol: "WETH", address: "0x4200000000000000000000000000000000000006" };

const meta: Meta<typeof TokenChip> = {
  title: "Primitives/TokenChip",
  component: TokenChip,
};
export default meta;

type Story = StoryObj<typeof TokenChip>;

export const Display: Story = {
  args: { token: usdc, variant: "display" },
};

export const ToggleSelected: Story = {
  args: { token: usdc, variant: "toggle", selected: true },
};

export const ToggleUnselected: Story = {
  args: { token: weth, variant: "toggle", selected: false },
};

export const Removable: Story = {
  args: { token: usdc, variant: "removable" },
};
