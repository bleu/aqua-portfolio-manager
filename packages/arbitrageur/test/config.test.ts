import { describe, expect, it } from "vitest";
import { parseStrategies } from "../src/config.js";

const MAKER = "0x1111111111111111111111111111111111111111";
const TOKEN_A = "0x2222222222222222222222222222222222222222";
const FEED_A = "0x3333333333333333333333333333333333333333";
const TOKEN_B = "0x4444444444444444444444444444444444444444";
const FEED_B = "0x5555555555555555555555555555555555555555";

function validStrategy(overrides: Record<string, unknown> = {}) {
  return {
    orderMaker: MAKER,
    orderTraits: "0",
    orderData: "0x",
    groupA: [{ token: TOKEN_A, feed: FEED_A }],
    groupB: [{ token: TOKEN_B, feed: FEED_B }],
    ...overrides,
  };
}

describe("parseStrategies", () => {
  it("parses a single valid strategy", () => {
    const strategies = parseStrategies([validStrategy()]);
    expect(strategies).toHaveLength(1);
    expect(strategies[0]).toEqual({
      order: { maker: MAKER, traits: 0n, data: "0x" },
      groupA: [{ token: TOKEN_A, feed: FEED_A }],
      groupB: [{ token: TOKEN_B, feed: FEED_B }],
    });
  });

  it("parses multiple strategies, each with its own order and basket", () => {
    const strategies = parseStrategies([validStrategy(), validStrategy({ orderTraits: "7" })]);
    expect(strategies).toHaveLength(2);
    expect(strategies[1]!.order.traits).toBe(7n);
  });

  it("rejects a non-array top level", () => {
    expect(() => parseStrategies({})).toThrow(/non-empty JSON array/);
  });

  it("rejects an empty array", () => {
    expect(() => parseStrategies([])).toThrow(/non-empty JSON array/);
  });

  it("rejects a strategy missing an order field", () => {
    const { orderData: _orderData, ...missingOrderData } = validStrategy();
    expect(() => parseStrategies([missingOrderData])).toThrow(/orderMaker\/orderTraits\/orderData/);
  });

  it("rejects a group entry missing token or feed", () => {
    expect(() => parseStrategies([validStrategy({ groupA: [{ token: TOKEN_A }] })])).toThrow(
      /groupA\[0\] must be/,
    );
  });

  it("rejects an empty group", () => {
    expect(() => parseStrategies([validStrategy({ groupB: [] })])).toThrow(/groupB must be a non-empty array/);
  });
});
