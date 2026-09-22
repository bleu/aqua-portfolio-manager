const WAD = 10n ** 18n;
const BPS_SCALE = 10_000n;

/// WAD-scaled USD value of `amountIn` units of a token priced at `priceInWad` (18-decimal oracle
/// price of one whole token) with `decimalsIn` on-chain decimals.
export function valueWad(amountIn: bigint, priceInWad: bigint, decimalsIn: number): bigint {
  return (amountIn * priceInWad) / 10n ** BigInt(decimalsIn);
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
/// not something encoded into strategy args.
export function profitBps(quotedOut: bigint, fairOut: bigint): bigint {
  if (fairOut === 0n) return 0n;
  return ((quotedOut - fairOut) * BPS_SCALE) / fairOut;
}

export interface Opportunity {
  amountIn: bigint;
  quotedOut: bigint;
  fairOut: bigint;
  profitBps: bigint;
}

/// Samples `steps` geometrically-spaced trade sizes between `minAmount` and `maxAmount` (log-
/// scale, so a wide min/max range still gets even coverage across orders of magnitude) and
/// returns whichever size cleared `minProfitBps` by the widest margin, or `undefined` if none
/// did. An approximation, not the true optimum -- see README's "Opportunity search" section for
/// why geometric sampling over a tighter search (e.g. ternary) was the right tradeoff here.
export async function findBestOpportunity(params: {
  minAmount: bigint;
  maxAmount: bigint;
  steps: number;
  minProfitBps: bigint;
  priceInWad: bigint;
  decimalsIn: number;
  priceOutWad: bigint;
  decimalsOut: number;
  quote: (amountIn: bigint) => Promise<bigint>;
}): Promise<Opportunity | undefined> {
  const { minAmount, maxAmount, steps, minProfitBps, priceInWad, decimalsIn, priceOutWad, decimalsOut, quote } =
    params;

  if (minAmount <= 0n || maxAmount <= minAmount || steps < 2) {
    throw new Error("invalid search bounds");
  }

  const sizes = geometricSteps(minAmount, maxAmount, steps);
  // Each size's quote is an independent read-only eth_call -- fetched concurrently rather than
  // one at a time, since `steps` sequential RPC round trips per leg adds up fast across a basket
  // with several legs.
  const quotedOuts = await Promise.all(sizes.map(quote));

  let best: Opportunity | undefined;

  for (let i = 0; i < sizes.length; i++) {
    const amountIn = sizes[i]!;
    const quotedOut = quotedOuts[i]!;
    const fairOut = fairAmountOut(amountIn, priceInWad, decimalsIn, priceOutWad, decimalsOut);
    const bps = profitBps(quotedOut, fairOut);

    if (bps >= minProfitBps && (best === undefined || bps > best.profitBps)) {
      best = { amountIn, quotedOut, fairOut, profitBps: bps };
    }
  }

  return best;
}

/// `steps` bigint sizes spaced evenly on a log scale between `min` and `max`, inclusive of both
/// endpoints. Interpolates in floating point (trade sizes are approximate search points, not
/// values requiring WAD-exact precision) and rounds back to bigint.
export function geometricSteps(min: bigint, max: bigint, steps: number): bigint[] {
  if (steps < 2) {
    throw new Error("geometricSteps requires at least 2 steps");
  }
  const logMin = Math.log(Number(min));
  const logMax = Math.log(Number(max));
  const result: bigint[] = [];
  for (let i = 0; i < steps; i++) {
    const t = i / (steps - 1);
    const value = Math.exp(logMin + t * (logMax - logMin));
    result.push(BigInt(Math.round(value)));
  }
  return result;
}

export { WAD, BPS_SCALE };
