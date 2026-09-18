import { describe, expect, it } from "vitest";
import { fairAmountOut, findBestOpportunity, geometricSteps, profitBps, valueWad } from "../src/pricing.js";

const WAD = 10n ** 18n;

describe("valueWad", () => {
  it("converts a token amount into WAD-scaled USD value", () => {
    // 2 tokens (18 decimals) at $2000/token (WAD price) = $4000, WAD-scaled.
    const amount = 2n * WAD;
    const priceWad = 2000n * WAD;
    expect(valueWad(amount, priceWad, 18)).toBe(4000n * WAD);
  });

  it("accounts for non-18 decimals", () => {
    // 5 USDC (6 decimals) at $1 = $5, WAD-scaled.
    const amount = 5_000_000n; // 5 * 1e6
    const priceWad = 1n * WAD;
    expect(valueWad(amount, priceWad, 6)).toBe(5n * WAD);
  });
});

describe("fairAmountOut", () => {
  it("returns an equal-value amount when prices match token-for-token", () => {
    // 1 ETH at $2000 should buy 2000 USDC (6 decimals) at $1.
    const amountIn = 1n * WAD;
    const priceInWad = 2000n * WAD;
    const priceOutWad = 1n * WAD;
    expect(fairAmountOut(amountIn, priceInWad, 18, priceOutWad, 6)).toBe(2000n * 1_000_000n);
  });

  it("throws on a zero output price", () => {
    expect(() => fairAmountOut(1n * WAD, 1n * WAD, 18, 0n, 18)).toThrow();
  });
});

describe("profitBps", () => {
  it("is zero when quoted matches fair exactly", () => {
    expect(profitBps(100n, 100n)).toBe(0n);
  });

  it("is positive when quoted exceeds fair", () => {
    // 110 vs 100 fair = +1000bps (10%)
    expect(profitBps(110n, 100n)).toBe(1000n);
  });

  it("is negative when quoted falls short of fair", () => {
    expect(profitBps(90n, 100n)).toBe(-1000n);
  });
});

describe("geometricSteps", () => {
  it("includes both endpoints and is monotonically increasing", () => {
    const steps = geometricSteps(1_000n, 1_000_000n, 5);
    expect(steps[0]).toBe(1_000n);
    expect(steps[steps.length - 1]).toBe(1_000_000n);
    for (let i = 1; i < steps.length; i++) {
      expect(steps[i]).toBeGreaterThan(steps[i - 1]);
    }
  });

  it("spans orders of magnitude evenly, not linearly", () => {
    const steps = geometricSteps(1n, 1_000_000n, 7);
    // Log-spaced over 6 orders of magnitude in 6 hops means each hop is ~10x, not ~166_666 apart.
    const ratio = Number(steps[1]) / Number(steps[0]);
    expect(ratio).toBeGreaterThan(5);
    expect(ratio).toBeLessThan(20);
  });
});

describe("findBestOpportunity", () => {
  /// A synthetic constant-product-style quote function: amountOut = amountIn * k / (amountIn + c),
  /// which concaves exactly like a real weighted-curve AMM's marginal price does -- good enough
  /// to exercise the search's ability to find an interior maximum, without needing a live chain.
  function syntheticQuote(k: bigint, c: bigint) {
    return async (amountIn: bigint) => (amountIn * k) / (amountIn + c);
  }

  it("finds a profitable size when the curve pays out above fair value", async () => {
    // Fair rate is 1:1 (priceIn == priceOut, same decimals). The synthetic curve pays out more
    // than amountIn for small trades (mispriced pool), tapering off as size grows.
    const result = await findBestOpportunity({
      minAmount: 10n,
      maxAmount: 100_000n,
      steps: 10,
      minProfitBps: 100n, // 1%
      priceInWad: WAD,
      decimalsIn: 18,
      priceOutWad: WAD,
      decimalsOut: 18,
      quote: syntheticQuote(1_500_000n, 1_000n), // pays > amountIn while amountIn is small
    });

    expect(result).toBeDefined();
    expect(result!.profitBps).toBeGreaterThanOrEqual(100n);
  });

  it("returns undefined when nothing clears the profit threshold", async () => {
    const result = await findBestOpportunity({
      minAmount: 10n,
      maxAmount: 100_000n,
      steps: 10,
      minProfitBps: 100n,
      priceInWad: WAD,
      decimalsIn: 18,
      priceOutWad: WAD,
      decimalsOut: 18,
      // Pays out less than amountIn always -- never profitable in either direction.
      quote: syntheticQuote(900_000n, 1_000_000n),
    });

    expect(result).toBeUndefined();
  });

  it("rejects invalid search bounds", async () => {
    await expect(
      findBestOpportunity({
        minAmount: 100n,
        maxAmount: 10n, // max < min
        steps: 5,
        minProfitBps: 0n,
        priceInWad: WAD,
        decimalsIn: 18,
        priceOutWad: WAD,
        decimalsOut: 18,
        quote: syntheticQuote(1n, 1n),
      }),
    ).rejects.toThrow();
  });
});
