const WAD = 10n ** 18n;
const BPS_SCALE = 10_000n;

/// WAD-scaled USD value of `amountIn` units of a token priced at `priceInWad` (18-decimal oracle
/// price of one whole token) with `decimalsIn` on-chain decimals.
export function valueWad(amountIn: bigint, priceInWad: bigint, decimalsIn: number): bigint {
  return (amountIn * priceInWad) / 10n ** BigInt(decimalsIn);
}

/// Inverse of `valueWad`: how many of a `decimalsIn`-decimal token, priced at `priceInWad`, are
/// worth `usdWad`. Used to turn a USD-denominated search bound into a raw tokenIn amount per leg
/// -- a single raw-unit bound can't sensibly cover tokens spanning different decimals (e.g. an
/// 18-decimal WETH leg and a 6-decimal USDC leg in the same basket), so bounds are configured in
/// USD and converted here, per leg, instead.
export function amountForUsdWad(usdWad: bigint, priceInWad: bigint, decimalsIn: number): bigint {
  if (priceInWad === 0n) {
    throw new Error("priceInWad must be non-zero");
  }
  return (usdWad * 10n ** BigInt(decimalsIn)) / priceInWad;
}

/// The `tokenOut` amount that would exactly preserve `amountIn`'s oracle value -- the "fair",
/// no-arbitrage exchange rate PM's own curve is supposed to track (see PM's own price-deviation
/// circuit breaker, which checks exactly this ratio on-chain).
export function fairAmountOut(
  amountIn: bigint,
  priceInWad: bigint,
  decimalsIn: number,
  priceOutWad: bigint,
  decimalsOut: number,
): bigint {
  if (priceOutWad === 0n) {
    throw new Error("priceOutWad must be non-zero");
  }
  const usdValueWad = valueWad(amountIn, priceInWad, decimalsIn);
  return (usdValueWad * 10n ** BigInt(decimalsOut)) / priceOutWad;
}

/// Profit as basis points (1/10_000) of the fair value of the trade -- standard bps, distinct
/// from PM's own on-chain `PM_BPS` (1e9) convention, since this is a plain off-chain comparison,
/// not something encoded into strategy args. Kept for logging/diagnostics; candidate selection
/// itself ranks on `profitUsdWad`, not this.
export function profitBps(quotedOut: bigint, fairOut: bigint): bigint {
  if (fairOut === 0n) return 0n;
  return ((quotedOut - fairOut) * BPS_SCALE) / fairOut;
}

/// WAD-scaled USD profit of the trade: the tokenOut received beyond fair value, priced via
/// `priceOutWad`. A dollar floor holds up better than a relative bps one -- it's what actually
/// has to cover gas, and doesn't erode in an arbitrage race-to-the-bottom the way a percentage
/// does. Negative when the trade pays out less than fair.
export function profitUsdWad(quotedOut: bigint, fairOut: bigint, priceOutWad: bigint, decimalsOut: number): bigint {
  return valueWad(quotedOut - fairOut, priceOutWad, decimalsOut);
}

export interface Opportunity {
  amountIn: bigint;
  quotedOut: bigint;
  fairOut: bigint;
  profitBps: bigint;
  profitUsdWad: bigint;
}

/// Balancer's closed-form "In-Given-Price" formula (whitepaper eq. 21: `A_i = B_i * ((SP'/SP)^
/// (W_o/(W_o+W_i)) - 1)`), adapted for this curve's own group-level pricing (PortfolioManagerSwap
/// prices cross-group trades on each GROUP's total oracle value, not per-token balances -- see
/// PortfolioManagerPricing.sol's `spotPrice`, `SP = (B_i/W_i)/(B_o/W_o)`, which is exactly
/// Balancer's own weighted-pool spot price applied to group values) and for the fee this curve
/// applies to input before it enters the invariant (`exactIn`'s `amountInEff`), which the
/// whitepaper's base formula doesn't include.
///
/// Target is always perfect group-weight equilibrium (`SP' = WAD`): both groups exactly at their
/// configured target share of total portfolio value. That's this design's own definition of
/// "fair" (see PortfolioManagerSwap's price-deviation check, which tests the same ratio against
/// 1), not an external market price the way a generic Balancer pool's arbitrageur would use --
/// this system has no such external reference for two arbitrary groups.
///
/// Replaces a geometric-step search entirely: computes the exact trade value directly instead of
/// sampling candidate sizes and picking the best. Uses floating point, not WAD-exact fixed-point
/// math -- deliberately: the result is a starting point for exactly one real `quoteExactIn`
/// verification (see candidateEvaluation.ts), not the trade's final source of truth, so it
/// doesn't need to replicate the contract's own rounding.
///
/// Returns 0 when trading `groupIn` for `groupOut` would push the price further from equilibrium,
/// not closer -- the profitable direction is always the opposite leg (which `evaluateStrategy`
/// also evaluates, since every group pair is tried both ways).
export function inGivenPriceValueWad(params: {
  groupInValueWad: bigint;
  groupOutValueWad: bigint;
  weightInWad: bigint;
  weightOutWad: bigint;
  feeWad: bigint;
}): bigint {
  const { groupInValueWad, groupOutValueWad, weightInWad, weightOutWad, feeWad } = params;
  if (groupInValueWad <= 0n || groupOutValueWad <= 0n || weightInWad <= 0n || weightOutWad <= 0n) return 0n;

  // ratio = SP'/SP, with SP' = 1 (WAD) and SP = (B_i/W_i)/(B_o/W_o):
  // ratio = B_o * W_i / (B_i * W_o)
  const ratio = (Number(groupOutValueWad) * Number(weightInWad)) / (Number(groupInValueWad) * Number(weightOutWad));
  if (!Number.isFinite(ratio) || ratio <= 0) return 0n;

  const exponent = Number(weightOutWad) / (Number(weightOutWad) + Number(weightInWad));
  const poweredRatio = ratio ** exponent;
  if (poweredRatio <= 1) return 0n; // this direction moves the price further from equilibrium

  const amountInEffective = Number(groupInValueWad) * (poweredRatio - 1);
  const feeFraction = Number(feeWad) / Number(WAD);
  const amountInGross = amountInEffective / (1 - feeFraction);
  if (!Number.isFinite(amountInGross) || amountInGross <= 0) return 0n;

  return BigInt(Math.round(amountInGross));
}

export { WAD, BPS_SCALE };
