import type { Meta, StoryObj } from "@storybook/react";
import { getAddress } from "viem";
import { PortfolioManagerHistoryPage } from "./PortfolioManagerHistoryPage";
import { DAI, USDC, USDT, WBTC, WETH } from "@/lib/mockData";
import { buildOrder, buildProgram, encodeOrder } from "@/lib/portfolioManagerEncoding";
import type { StrategyHistoryEntry } from "@/lib/useStrategyHistory";

const meta: Meta<typeof PortfolioManagerHistoryPage> = {
  title: "Pages/PortfolioManagerHistory",
  component: PortfolioManagerHistoryPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof PortfolioManagerHistoryPage>;

const network = "Ethereum";
const safeAddress = "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B";
// This repo's literal "Safe address" placeholder (reused across many story files as plain display
// text elsewhere) isn't actually EIP-55 checksum-valid -- only surfaced here because this story is
// the first to really ABI-encode it via encodeOrder/buildOrder, which viem validates strictly.
const maker = getAddress(safeAddress.toLowerCase());

const tokensBySymbol: Record<string, { symbol: string; address: string }> = { USDC, USDT, DAI, WETH, WBTC };
function symbolForToken(address: string): string {
  const match = Object.values(tokensBySymbol).find((t) => t.address.toLowerCase() === address.toLowerCase());
  return match?.symbol ?? address.slice(0, 6);
}

/** Real ABI-encoded order bytes, not hand-written hex -- built the same way the real wizard does,
 *  so decodeOrderParameters (fee/deviation shown on each card) decodes something real. */
function fakeEncodedOrder(feeBps: bigint, maxDeviationBps: bigint) {
  const program = buildProgram(
    [
      { weightWad: 667_000_000_000_000_000n, members: [{ tokenIndex: 1, feedIndex: 0 }] },
      { weightWad: 333_000_000_000_000_000n, members: [{ tokenIndex: 2, feedIndex: 0 }] },
    ],
    feeBps,
    maxDeviationBps,
  );
  return encodeOrder(buildOrder(maker, program));
}

const activeEntry: StrategyHistoryEntry = {
  strategyHash: "0xaaaa111122223333444455556666777788889999aaaabbbbccccddddeeeeff",
  encodedOrder: fakeEncodedOrder(20_000_000n, 10_000_000n),
  tokens: [USDC.address, WETH.address],
  groupNames: ["Stablecoins", "Crypto majors"],
  isActive: true,
  shippedAt: String(Math.floor(Date.now() / 1000) - 3 * 86_400),
  shippedAtTxHash: "0x8a2f1234aaaa1234bbbb1234cccc1234dddd1234eeee1234ffff123430c1",
  dockedAt: null,
  dockedAtTxHash: null,
};

const dockedEntry: StrategyHistoryEntry = {
  strategyHash: "0xbbbb222233334444555566667777888899990000aaaabbbbccccddddeeefff0",
  encodedOrder: fakeEncodedOrder(50_000_000n, 20_000_000n),
  tokens: [USDT.address, DAI.address, WBTC.address],
  groupNames: ["Stablecoins", "Crypto majors"],
  isActive: false,
  shippedAt: String(Math.floor(Date.now() / 1000) - 10 * 86_400),
  shippedAtTxHash: "0x7b3e9876dddd9876cccc9876bbbb9876aaaa98769999876655558765432d2",
  dockedAt: String(Math.floor(Date.now() / 1000) - 3 * 86_400),
  dockedAtTxHash: "0x9c4fabcdeeeeabcdddddabcdccccabcdbbbbabcdaaaaabcd99998765210e3",
};

export const WithHistory: Story = {
  args: {
    network,
    safeAddress,
    entries: [activeEntry, dockedEntry],
    isLoading: false,
    symbolForToken,
    onReship: () => {},
  },
};

export const Empty: Story = {
  args: {
    network,
    safeAddress,
    entries: [],
    isLoading: false,
    symbolForToken,
  },
};

export const Loading: Story = {
  args: {
    network,
    safeAddress,
    entries: undefined,
    isLoading: true,
    symbolForToken,
  },
};
