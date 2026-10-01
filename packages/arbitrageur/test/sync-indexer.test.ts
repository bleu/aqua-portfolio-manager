import { describe, expect, it } from "vitest";
import { normalizeToWad, parseCursor, formatCursor } from "../src/sync/indexer.js";

describe("normalizeToWad", () => {
  it("scales an 8-decimal Chainlink answer up to 18-decimal WAD", () => {
    // $83,545.15 at 8 decimals, a realistic BTC/USD Chainlink reading.
    expect(normalizeToWad(8354515784949n, 8)).toBe(83545157849490000000000n);
  });

  it("is a no-op at 18 decimals", () => {
    expect(normalizeToWad(123456789n, 18)).toBe(123456789n);
  });

  it("scales a >18-decimal answer down", () => {
    expect(normalizeToWad(123n * 10n ** 20n, 20)).toBe(123n * 10n ** 18n);
  });
});

describe("cursor round-trip", () => {
  it("formats and parses back to the same (block, logIndex)", () => {
    const formatted = formatCursor(51908096n, 42);
    expect(formatted).toBe("51908096:42");
    expect(parseCursor(formatted)).toEqual({ block: 51908096n, logIndex: 42 });
  });

  it("treats a missing cursor as before-genesis, not zero-inclusive", () => {
    // logIndex -1 so the very first indexed row (block 0, logIndex 0) still compares as after it.
    expect(parseCursor(undefined)).toEqual({ block: 0n, logIndex: -1 });
  });
});
