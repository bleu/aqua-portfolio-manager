import { describe, expect, it } from "vitest";
import { fairAmountOut, findBestOpportunity, geometricSteps, profitBps, profitUsdWad, valueWad } from "../src/pricing.js";

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

describe("profitUsdWad", () => {
  it("is zero when quoted matches fair exactly", () => {
    expect(profitUsdWad(100n * WAD, 100n * WAD, WAD, 18)).toBe(0n);
  });

  it("prices the excess tokenOut in USD via priceOutWad", () => {
    // 10 extra tokens at $2000/token = $20,000 profit, WAD-scaled.
    expect(profitUsdWad(110n * WAD, 100n * WAD, 2000n * WAD, 18)).toBe(20_000n * WAD);
  });

  it("is negative when quoted falls short of fair", () => {
    expect(profitUsdWad(90n * WAD, 100n * WAD, WAD, 18)).toBe(-10n * WAD);
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

  it("throws a clear error instead of dividing by zero for fewer than 2 steps", () => {
    expect(() => geometricSteps(1n, 1_000n, 1)).toThrow(/at least 2 steps/);
    expect(() => geometricSteps(1n, 1_000n, 0)).toThrow(/at least 2 steps/);
  });
});

describe("findBestOpportunity", () => {
  /// A synthetic constant-product-style quote function: amountOut = amountIn * k / (amountIn + c),
  /// which concaves exactly like a real weighted-curve AMM's marginal price does -- good enough
  /// to exercise the search's ability to find an interior maximum, without needing a live chain.
  /// `k` and `c` must be on the same scale as `amountIn` (WAD, here) -- an unscaled `k` makes the
  /// curve's large-amountIn asymptote negligible next to a WAD-scaled fair value, so every size
  /// reads as unprofitable regardless of the curve's intended shape.
  function syntheticQuote(k: bigint, c: bigint) {
    return async (amountIn: bigint) => (amountIn * k) / (amountIn + c);
  }

  it("finds a profitable size when the curve pays out above fair value", async () => {
    // Fair rate is 1:1 (priceIn == priceOut, same decimals, so $1 == 1 WAD token here). Amounts
    // are WAD-scaled (real 18-decimal token units), not raw integers -- a $1 profit floor is
    // meaningless against amountIn values smaller than a wei-fraction of a token. The synthetic
    // curve pays out more than amountIn for small trades (mispriced pool), tapering off as size
    // grows; `c` is scaled alongside the amount range so the curve's shape (profitable-small,
    // tapering-large) is preserved at this new scale.
    const result = await findBestOpportunity({
      minAmount: 10n * WAD,
      maxAmount: 100_000n * WAD,
      steps: 10,
      minProfitUsdWad: 1n * WAD, // $1
      priceInWad: WAD,
      decimalsIn: 18,
      priceOutWad: WAD,
      decimalsOut: 18,
      quote: syntheticQuote(1_500_000n * WAD, 1_000n * WAD), // pays > amountIn while amountIn is small
    });

    expect(result).toBeDefined();
    expect(result!.profitUsdWad).toBeGreaterThanOrEqual(1n * WAD);
  });

  it("returns undefined when nothing clears the profit threshold", async () => {
    const result = await findBestOpportunity({
      minAmount: 10n * WAD,
      maxAmount: 100_000n * WAD,
      steps: 10,
      minProfitUsdWad: 1n * WAD,
      priceInWad: WAD,
      decimalsIn: 18,
      priceOutWad: WAD,
      decimalsOut: 18,
      // Pays out less than amountIn always -- never profitable in either direction.
      quote: syntheticQuote(900_000n * WAD, 1_000_000n * WAD),
    });

    expect(result).toBeUndefined();
  });

  it("rejects invalid search bounds", async () => {
    await expect(
      findBestOpportunity({
        minAmount: 100n,
        maxAmount: 10n, // max < min
        steps: 5,
        minProfitUsdWad: 0n,
        priceInWad: WAD,
        decimalsIn: 18,
        priceOutWad: WAD,
        decimalsOut: 18,
        quote: syntheticQuote(1n, 1n),
      }),
    ).rejects.toThrow();
  });
});
