import type { Meta, StoryObj } from "@storybook/react";
import { getBasketColor } from "@/lib/basketColors";
import { PRICE_LIMIT_BLOCKED_MESSAGE, ReviewPortfolioManagerPage } from "./ReviewPortfolioManagerPage";

const meta: Meta<typeof ReviewPortfolioManagerPage> = {
  title: "Pages/ReviewPortfolioManager",
  component: ReviewPortfolioManagerPage,
  parameters: { layout: "fullscreen" },
};
export default meta;

type Story = StoryObj<typeof ReviewPortfolioManagerPage>;

const baskets = [
  {
    id: "stablecoins",
    name: "Stablecoins",
    color: getBasketColor(0).solid,
    tokenSymbols: ["USDC", "USDT", "DAI"],
    currentPct: 66.7,
    currentValue: 10000,
    targetPct: 66.7,
  },
  {
    id: "crypto-majors",
    name: "Crypto majors",
    color: getBasketColor(1).solid,
    tokenSymbols: ["WETH", "WBTC", "wstETH"],
    currentPct: 33.3,
    currentValue: 5000,
    targetPct: 33.3,
  },
];

export const NoRebalanceNeeded: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets,
    priceDeviationPct: 1,
    lpFeePct: 2,
    signaturesRequired: 3,
  },
};

export const RebalanceExpected: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets: [
      { ...baskets[0], targetPct: 50 },
      { ...baskets[1], targetPct: 50 },
    ],
    priceDeviationPct: 1,
    lpFeePct: 2,
    signaturesRequired: 2,
  },
};

/** docs/adr/0011's basket-scope-guard check, both conflict reasons at once -- see
 *  BasketScopeGuard.sol's CrossBasketStrategyForbidden and TokenNotInAnyBasket. */
export const BasketScopeConflicts: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets,
    priceDeviationPct: 1,
    lpFeePct: 2,
    signaturesRequired: 1,
    scopeConflicts: [
      {
        strategyHash: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        app: "0x1111111111111111111111111111111111111111",
        types: ["cross-basket"],
        basketNames: ["Stablecoins", "Crypto majors"],
        foreignTokens: [],
      },
      {
        strategyHash: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        app: "0x2222222222222222222222222222222222222222",
        types: ["basket-foreign"],
        basketNames: [],
        foreignTokens: ["0x3333333333333333333333333333333333333333"],
      },
    ],
  },
};

/** Aqua.ship() permanently refuses to reuse a strategyHash once shipped, even after docking
 *  (Aqua.sol's StrategiesMustBeImmutable) -- recreating identical parameters hits this. */
export const AlreadyShipped: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets,
    priceDeviationPct: 1,
    lpFeePct: 2,
    signaturesRequired: 1,
    alreadyShipped: true,
  },
};

/** The TransactionOutcomeModal's generic-failure variant, confirmed against the Claude Artifact's
 *  Outcome_Failed.dc.html. Reached when proposing the Safe transaction itself throws, which
 *  happens while still on Review -- before any Pending/signing flow starts. */
export const TransactionFailed: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets,
    priceDeviationPct: 1,
    lpFeePct: 2,
    signaturesRequired: 1,
    createTransactionError: "Something went wrong creating this transaction. Try again, or contact the team if this keeps happening.",
  },
};

/** The TransactionOutcomeModal's blocked-by-price-limit variant, confirmed verbatim against the
 *  Claude Artifact's Outcome_Blocked.dc.html (same heading/body copy, byte-for-byte). */
export const TransactionBlocked: Story = {
  args: {
    network: "Ethereum",
    safeAddress: "0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B",
    baskets,
    priceDeviationPct: 1,
    lpFeePct: 2,
    signaturesRequired: 1,
    createTransactionError: PRICE_LIMIT_BLOCKED_MESSAGE,
  },
};
