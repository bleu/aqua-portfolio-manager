import { describe, expect, it, vi } from "vitest";
import type { PublicClient } from "viem";
import { readUsablePrices } from "../src/index.js";

const GOOD_FEED_1 = "0x1111111111111111111111111111111111111111";
const GOOD_FEED_2 = "0x2222222222222222222222222222222222222222";
const STALE_FEED = "0x3333333333333333333333333333333333333333";

const NOW = 1_000_000n;
const MAX_STALENESS_SECONDS = 3600;

/// Fakes just the two calls `readOraclePriceWad` actually makes -- `decimals` and
/// `latestRoundData` per feed, plus one shared `getBlock()` -- rather than a real client.
/// `STALE_FEED`'s `updatedAt` is far enough in the past to trip `readOraclePriceWad`'s own
/// staleness check, exercising the real failure path `readUsablePrices` is meant to isolate.
function fakeClient(): PublicClient {
  const readContract = vi.fn(async ({ address, functionName }: { address: string; functionName: string }) => {
    if (functionName === "decimals") return 8;
    if (functionName === "latestRoundData") {
      const updatedAt = address === STALE_FEED ? NOW - 100_000n : NOW - 10n;
      return [0n, 200_000_000n, 0n, updatedAt, 0n];
    }
    throw new Error(`unexpected call: ${functionName}`);
  });
  const getBlock = vi.fn(async () => ({ timestamp: NOW }));
  return { readContract, getBlock } as unknown as PublicClient;
}

describe("readUsablePrices", () => {
  it("returns prices for every feed when all resolve", async () => {
    const prices = await readUsablePrices(fakeClient(), [GOOD_FEED_1, GOOD_FEED_2], MAX_STALENESS_SECONDS);
    expect(prices.size).toBe(2);
    expect(prices.has(GOOD_FEED_1)).toBe(true);
    expect(prices.has(GOOD_FEED_2)).toBe(true);
  });

  it("isolates one stale feed's failure -- the other feeds still resolve", async () => {
    const prices = await readUsablePrices(fakeClient(), [GOOD_FEED_1, STALE_FEED, GOOD_FEED_2], MAX_STALENESS_SECONDS);
    expect(prices.size).toBe(2);
    expect(prices.has(GOOD_FEED_1)).toBe(true);
    expect(prices.has(GOOD_FEED_2)).toBe(true);
    expect(prices.has(STALE_FEED)).toBe(false);
  });

  it("returns an empty map, not a rejection, when every feed fails", async () => {
    const prices = await readUsablePrices(fakeClient(), [STALE_FEED], MAX_STALENESS_SECONDS);
    expect(prices.size).toBe(0);
  });
});
