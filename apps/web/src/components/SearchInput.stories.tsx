import type { Meta, StoryObj } from "@storybook/react";
import { SearchInput } from "./SearchInput";

const meta: Meta<typeof SearchInput> = {
  title: "Primitives/SearchInput",
  component: SearchInput,
};
export default meta;

type Story = StoryObj<typeof SearchInput>;

export const Empty: Story = {
  args: { placeholder: "Search by token name or address" },
};

export const WithValue: Story = {
  args: { placeholder: "Search by token name or address", defaultValue: "USDC" },
};
