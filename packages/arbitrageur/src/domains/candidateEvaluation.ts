import { eq } from "drizzle-orm";
import type { Address, Hex, PublicClient } from "viem";
import type { Db } from "../db/client.js";
import { strategies, feedPrices, candidates } from "../db/schema.js";
import { decodeProgram, type DecodedGroup } from "./programDecoder.js";
import { decodeOrder, extractProgram } from "./orderDecoder.js";
import { findBestOpportunity, type Opportunity } from "../pricing.js";
import { getFyndSwapCalldata, type FyndClient } from "../fynd.js";
import { quoteExactIn, tokenDecimals } from "../chain.js";

export interface Leg {
  tokenIn: Address;
  tokenOut: Address;
  feedIn: Address;
  feedOut: Address;
}

/// Every member of one group traded against every member of the other, both directions -- the PM
/// curve only ever prices a trade between two *different* declared groups
/// (PortfolioManagerSwap._resolve's groupInIdx != groupOutIdx check).
export function buildLegs(groups: DecodedGroup[]): Leg[] {
  const legs: Leg[] = [];
  for (let i = 0; i < groups.length; i++) {
    for (let j = 0; j < groups.length; j++) {
      if (i === j) continue;
      for (const a of groups[i]!.members) {
        for (const b of groups[j]!.members) {
          legs.push({ tokenIn: a.token, tokenOut: b.token, feedIn: a.feed, feedOut: b.feed });
        }
      }
    }
  }
  return legs;
}

export interface UsablePrice {
  priceWad: bigint;
  blockTimestamp: bigint;
}

/// Price State read: the latest indexed price for a feed, or undefined if there is none yet or
/// it's older than `maxStalenessSeconds` (measured against the price's own reported block time,
/// not against when this function runs -- the indexer itself can lag, and a price that was fresh
/// when indexed but hasn't been followed by a newer one in a while is exactly what "stale" means
/// here).
export async function readUsablePrice(
  db: Db,
  feedProxy: Address,
  nowSeconds: bigint,
  maxStalenessSeconds: bigint,
): Promise<UsablePrice | undefined> {
  const row = await db.query.feedPrices.findFirst({ where: eq(feedPrices.feedProxy, feedProxy) });
  if (!row) return undefined;
  if (nowSeconds - row.blockTimestamp > maxStalenessSeconds) return undefined;
  return { priceWad: row.priceWad, blockTimestamp: row.blockTimestamp };
}

export interface CandidateEvaluationConfig {
  minTradeAmount: bigint;
  maxTradeAmount: bigint;
  searchSteps: number;
  minProfitUsdWad: bigint;
  maxPriceStalenessSeconds: bigint;
  fyndSlippageBps: bigint;
  fyndMinResponses: number;
  fyndTimeoutMs: number;
  slippageBufferBps: bigint;
  deadlineBufferSeconds: number;
  arbitrageurAddress: Address;
}

/// Candidate Evaluation domain: for one Strategy at one State Version, screens every cross-group
/// leg with the cheap oracle-fair-value pre-filter (reused from src/pricing.ts, unchanged since
/// the static-config experiment -- same math, different price source), then gets a real Fynd
/// quote only for the leg that passed, and ranks by Profit Headroom (ADR-0014's own metric: the
/// real route's expected return, less principal, less the return-token value of the Profit
/// Floor). Returns undefined when nothing clears the bar -- callers should not enqueue a
/// simulate-candidate job in that case.
///
/// Deliberate simplification from the ADR's own phrasing ("uses ... TypeScript contract math" for
/// the pre-filter): the curve quote itself still comes from a live `quoteExactIn` eth_call, not a
/// TypeScript reimplementation of the curve's own pricing formula. That eth_call is cheap
/// (read-only, no gas) and already correct -- reimplementing PM's weighted-curve math in
/// TypeScript to avoid it is a real, separate optimization, not a correctness requirement, and
/// risks silently diverging from the Solidity implementation it would have to mirror exactly.
export async function evaluateStrategy(
  db: Db,
  publicClient: PublicClient,
  fyndClient: FyndClient,
  strategyId: string,
  stateVersion: string,
  config: CandidateEvaluationConfig,
): Promise<string | undefined> {
  const strategy = await db.query.strategies.findFirst({ where: eq(strategies.id, strategyId) });
  if (!strategy || !strategy.isActive || strategy.ineligibilityReason !== null) return undefined;

  // The real Order, decoded from what Shipped actually carries -- not reconstructed or guessed.
  // `order.traits` in particular can't be inferred (it's a maker-chosen packed bitfield, not a PM
  // convention), so quoteExactIn's Order argument below uses this decode's own maker/traits/data
  // directly, never a hand-built stand-in. See src/domains/orderDecoder.ts.
  const order = decodeOrder(strategy.encodedOrder as Hex);
  const program = extractProgram(order.traits, order.data);
  const decoded = decodeProgram(program);
  const legs = buildLegs(decoded.groups);
  const nowSeconds = BigInt(Math.floor(Date.now() / 1000));

  let best: { leg: Leg; opportunity: Opportunity } | undefined;
  for (const leg of legs) {
    const [priceIn, priceOut] = await Promise.all([
      readUsablePrice(db, leg.feedIn, nowSeconds, config.maxPriceStalenessSeconds),
      readUsablePrice(db, leg.feedOut, nowSeconds, config.maxPriceStalenessSeconds),
    ]);
    if (!priceIn || !priceOut) continue; // one bad/missing feed skips only this leg, per #16b

    const [decimalsIn, decimalsOut] = await Promise.all([
      tokenDecimals(publicClient, leg.tokenIn),
      tokenDecimals(publicClient, leg.tokenOut),
    ]);

    const opportunity = await findBestOpportunity({
      minAmount: config.minTradeAmount,
      maxAmount: config.maxTradeAmount,
      steps: config.searchSteps,
      minProfitUsdWad: config.minProfitUsdWad,
      priceInWad: priceIn.priceWad,
      decimalsIn,
      priceOutWad: priceOut.priceWad,
      decimalsOut,
      quote: (amountIn) =>
        quoteExactIn(publicClient, config.arbitrageurAddress, order, leg.tokenIn, leg.tokenOut, amountIn),
    });

    if (opportunity && (!best || opportunity.profitUsdWad > best.opportunity.profitUsdWad)) {
      best = { leg, opportunity };
    }
  }

  if (!best) return undefined;

  const { leg, opportunity } = best;
  const fyndQuote = await getFyndSwapCalldata(fyndClient, {
    tokenIn: leg.tokenOut,
    tokenOut: leg.tokenIn,
    amountIn: opportunity.quotedOut,
    sender: config.arbitrageurAddress,
    slippageBps: config.fyndSlippageBps,
    minResponses: config.fyndMinResponses,
    timeoutMs: config.fyndTimeoutMs,
  });

  // Profit Floor, converted into tokenIn's own terms via its own oracle price -- Profit Headroom
  // is denominated in the return token (ADR-0014's Price and slippage rules), not USD.
  const priceIn = await readUsablePrice(db, leg.feedIn, nowSeconds, config.maxPriceStalenessSeconds);
  if (!priceIn) return undefined; // the feed went stale between the pre-filter pass and here
  const decimalsIn = await tokenDecimals(publicClient, leg.tokenIn);
  const profitFloorInTokenIn = (config.minProfitUsdWad * 10n ** BigInt(decimalsIn)) / priceIn.priceWad;
  const profitHeadroom = fyndQuote.expectedAmountOut - opportunity.amountIn - profitFloorInTokenIn;
  if (profitHeadroom <= 0n) return undefined;

  const minCurveAmountOut =
    opportunity.quotedOut - (opportunity.quotedOut * config.slippageBufferBps) / 10_000n;
  const deadline = BigInt(Math.floor(Date.now() / 1000) + config.deadlineBufferSeconds);
  const candidateId = `${strategyId}-${leg.tokenIn}-${leg.tokenOut}-${stateVersion}`;

  await db
    .insert(candidates)
    .values({
      id: candidateId,
      strategyId,
      tokenIn: leg.tokenIn,
      tokenOut: leg.tokenOut,
      amountIn: opportunity.amountIn,
      quotedOut: opportunity.quotedOut,
      fairOut: opportunity.fairOut,
      profitUsdWad: opportunity.profitUsdWad,
      profitHeadroom,
      fyndTarget: fyndQuote.target,
      fyndSpender: fyndQuote.spender,
      fyndCalldata: fyndQuote.calldata,
      minCurveAmountOut,
      deadline,
      stateVersion,
      status: "eligible",
    })
    .onConflictDoNothing();

  return candidateId;
}
