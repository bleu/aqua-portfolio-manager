import { describe, expect, it } from "vitest";
import { findConflicts, type IndexedStrategy } from "./useBasketScopeConflict";

const USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" as const;
const USDT = "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2" as const;
const WETH = "0x4200000000000000000000000000000000000006" as const;
const FOREIGN_TOKEN = "0x0000000000000000000000000000000000000001" as const;

const BASKETS = [
  { name: "Stables", tokenAddresses: [USDC, USDT] },
  { name: "Majors", tokenAddresses: [WETH] },
];

function strategy(overrides: Partial<IndexedStrategy>): IndexedStrategy {
  return { id: "s1", app: "0xapp0000000000000000000000000000000000000", strategyHash: "0xhash", tokens: [], ...overrides };
}

describe("findConflicts", () => {
  it("flags cross-basket when tokens span more than one basket", () => {
    const conflicts = findConflicts([strategy({ tokens: [USDC, WETH] })], BASKETS);
    expect(conflicts).toHaveLength(1);
    expect(conflicts[0]!.types).toEqual(["cross-basket"]);
    expect(conflicts[0]!.basketNames.sort()).toEqual(["Majors", "Stables"]);
  });

  it("flags basket-foreign when a token isn't declared in any basket, matching BasketScopeGuard.sol's TokenNotInAnyBasket", () => {
    const conflicts = findConflicts([strategy({ tokens: [USDC, FOREIGN_TOKEN] })], BASKETS);
    expect(conflicts).toHaveLength(1);
    expect(conflicts[0]!.types).toEqual(["basket-foreign"]);
    expect(conflicts[0]!.foreignTokens).toEqual([FOREIGN_TOKEN]);
  });

  it("flags both reasons when a strategy spans baskets and also holds a foreign token", () => {
    const conflicts = findConflicts([strategy({ tokens: [USDC, WETH, FOREIGN_TOKEN] })], BASKETS);
    expect(conflicts).toHaveLength(1);
    expect(conflicts[0]!.types.sort()).toEqual(["basket-foreign", "cross-basket"]);
  });

  it("does not flag a strategy fully contained in a single basket", () => {
    expect(findConflicts([strategy({ tokens: [USDC, USDT] })], BASKETS)).toHaveLength(0);
  });

  it("is case-insensitive when matching token addresses", () => {
    const conflicts = findConflicts([strategy({ tokens: [USDC.toLowerCase() as typeof USDC, WETH.toUpperCase() as typeof WETH] })], BASKETS);
    expect(conflicts).toHaveLength(1);
    expect(conflicts[0]!.types).toEqual(["cross-basket"]);
  });
});
