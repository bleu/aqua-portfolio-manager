import { describe, expect, it } from "vitest";
import { fairAmountOut, inGivenPriceValueWad, profitBps, profitUsdWad, valueWad } from "../src/pricing.js";

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

describe("inGivenPriceValueWad", () => {
  /// Independent check of what eq.21 (In-Given-Price) claims: trading the returned amount
  /// actually brings the curve's own spot price to equilibrium. Implements the curve's exactIn
  /// (whitepaper eq.15 / PortfolioManagerPricing.sol's exactIn, fee-exclusive here since the test
  /// cases below use feeWad: 0n) independently of pricing.ts, so this isn't just re-checking the
  /// same formula against itself -- it simulates the trade and re-measures the resulting price.
  function simulateSpotPriceAfterTrade(
    groupInValueWad: bigint,
    groupOutValueWad: bigint,
    weightInWad: bigint,
    weightOutWad: bigint,
    amountIn: bigint,
  ): number {
    const bIn = Number(groupInValueWad);
    const bOut = Number(groupOutValueWad);
    const wIn = Number(weightInWad);
    const wOut = Number(weightOutWad);
    const amountOut = bOut * (1 - (bIn / (bIn + Number(amountIn))) ** (wIn / wOut));
    const newIn = bIn + Number(amountIn);
    const newOut = bOut - amountOut;
    return newIn / wIn / (newOut / wOut);
  }

  it("brings an underweight group's curve price to equilibrium (equal weights)", () => {
    // groupIn ($15) is underweight relative to groupOut ($25) at equal 50/50 target weights --
    // SP = (15/0.5)/(25/0.5) = 0.6, below the 1.0 equilibrium target, so trading into groupIn is
    // the restoring direction.
    const groupInValueWad = 15n * WAD;
    const groupOutValueWad = 25n * WAD;
    const weightInWad = WAD / 2n;
    const weightOutWad = WAD / 2n;

    const amountIn = inGivenPriceValueWad({ groupInValueWad, groupOutValueWad, weightInWad, weightOutWad, feeWad: 0n });

    expect(amountIn).toBeGreaterThan(0n);
    const newSp = simulateSpotPriceAfterTrade(groupInValueWad, groupOutValueWad, weightInWad, weightOutWad, amountIn);
    expect(newSp).toBeCloseTo(1, 6);
  });

  it("returns 0 for the direction that would move price further from equilibrium", () => {
    // Same pool, opposite direction: groupOut ($25) is already overweight, so trading further
    // into it (as tokenIn) would push its price even further from equilibrium, not toward it.
    const amountIn = inGivenPriceValueWad({
      groupInValueWad: 25n * WAD,
      groupOutValueWad: 15n * WAD,
      weightInWad: WAD / 2n,
      weightOutWad: WAD / 2n,
      feeWad: 0n,
    });
    expect(amountIn).toBe(0n);
  });

  it("returns 0 when the pool is already at equilibrium", () => {
    const amountIn = inGivenPriceValueWad({
      groupInValueWad: 20n * WAD,
      groupOutValueWad: 20n * WAD,
      weightInWad: WAD / 2n,
      weightOutWad: WAD / 2n,
      feeWad: 0n,
    });
    expect(amountIn).toBe(0n);
  });

  it("still reaches equilibrium with unequal group weights", () => {
    // 70/30 target instead of 50/50 -- equilibrium is B_i/W_i == B_o/W_o, not B_i == B_o.
    const groupInValueWad = 10n * WAD;
    const groupOutValueWad = 30n * WAD;
    const weightInWad = (WAD * 7n) / 10n;
    const weightOutWad = (WAD * 3n) / 10n;

    const amountIn = inGivenPriceValueWad({ groupInValueWad, groupOutValueWad, weightInWad, weightOutWad, feeWad: 0n });

    expect(amountIn).toBeGreaterThan(0n);
    const newSp = simulateSpotPriceAfterTrade(groupInValueWad, groupOutValueWad, weightInWad, weightOutWad, amountIn);
    expect(newSp).toBeCloseTo(1, 6);
  });

  it("grosses the amount up by the fee so the net effective trade still reaches equilibrium", () => {
    // Same underweight pool as the first case, but with a 2% fee -- the curve charges the fee on
    // input before it reaches the invariant (PortfolioManagerPricing.sol's exactIn), so the gross
    // amount returned here must be larger than the fee-free case by exactly that margin.
    const groupInValueWad = 15n * WAD;
    const groupOutValueWad = 25n * WAD;
    const weightInWad = WAD / 2n;
    const weightOutWad = WAD / 2n;
    const feeWad = WAD / 50n; // 2%

    const grossAmountIn = inGivenPriceValueWad({ groupInValueWad, groupOutValueWad, weightInWad, weightOutWad, feeWad });
    const feeFreeAmountIn = inGivenPriceValueWad({
      groupInValueWad,
      groupOutValueWad,
      weightInWad,
      weightOutWad,
      feeWad: 0n,
    });

    expect(grossAmountIn).toBeGreaterThan(feeFreeAmountIn);
    // netAmountIn = grossAmountIn * (1 - fee) should reproduce the fee-free effective amount.
    const netAmountIn = (Number(grossAmountIn) * (1 - 0.02));
    expect(netAmountIn).toBeCloseTo(Number(feeFreeAmountIn), -1);
  });

  it("returns 0 for any non-positive input", () => {
    const base = { groupInValueWad: 15n * WAD, groupOutValueWad: 25n * WAD, weightInWad: WAD / 2n, weightOutWad: WAD / 2n, feeWad: 0n };
    expect(inGivenPriceValueWad({ ...base, groupInValueWad: 0n })).toBe(0n);
    expect(inGivenPriceValueWad({ ...base, groupOutValueWad: -1n })).toBe(0n);
    expect(inGivenPriceValueWad({ ...base, weightInWad: 0n })).toBe(0n);
    expect(inGivenPriceValueWad({ ...base, weightOutWad: 0n })).toBe(0n);
  });
});
