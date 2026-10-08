import type { Meta, StoryObj } from "@storybook/react";
import { CreateBasketsPage } from "./CreateBasketsPage";
import { initialBaskets, safeTokens } from "@/lib/mockBaskets";

const meta: Meta<typeof CreateBasketsPage> = {
  title: "Pages/CreateBaskets",
  component: CreateBasketsPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof CreateBasketsPage>;

export const TwoBasketsPrefilled: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets: initialBaskets,
    safeTokens,
  },
};

export const NoBasketsYet: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets: [{ id: "basket-1", name: "Basket 1", color: "#6366f1", tokenAddresses: [] }],
    safeTokens,
  },
};
