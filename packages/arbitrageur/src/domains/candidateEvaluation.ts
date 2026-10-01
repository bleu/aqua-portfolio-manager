import { eq } from "drizzle-orm";
import type { Address, Hex, PublicClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { Db } from "../db/client.js";
import { strategies, feedPrices, candidates } from "../db/schema.js";
import { decodeProgram, type DecodedGroup } from "./programDecoder.js";
import { decodeOrder, extractProgram } from "./orderDecoder.js";
import { inGivenPriceValueWad, fairAmountOut, profitBps, profitUsdWad, amountForUsdWad, valueWad, WAD } from "../pricing.js";
import { getFyndSwapCalldata, type FyndClient } from "../fynd.js";
import { quoteExactIn, tokenDecimals, tokenBalance } from "../chain.js";

export interface Leg {
  tokenIn: Address;
  tokenOut: Address;
  feedIn: Address;
  feedOut: Address;
  groupInIdx: number;
  groupOutIdx: number;
}

/// Every member of one group traded against every member of the other, both directions -- the PM
/// curve only ever prices a trade between two *different* declared groups
/// (PortfolioManagerSwap._resolve's groupInIdx != groupOutIdx check). Keeps each leg's group
/// indices so evaluateStrategy can price the group pair once and reuse it across every member
/// combination within it -- the in-given-price trade size only depends on group-level value and
/// weight, never on which specific member is traded (PortfolioManagerSwap prices cross-group
/// trades on each group's total oracle value, not per-token balances).
export function buildLegs(groups: DecodedGroup[]): Leg[] {
  const legs: Leg[] = [];
  for (let i = 0; i < groups.length; i++) {
    for (let j = 0; j < groups.length; j++) {
      if (i === j) continue;
      for (const a of groups[i]!.members) {
        for (const b of groups[j]!.members) {
          legs.push({ tokenIn: a.token, tokenOut: b.token, feedIn: a.feed, feedOut: b.feed, groupInIdx: i, groupOutIdx: j });
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

/// A group's total oracle value (WAD), matching PortfolioManagerSwap._groupValueWad exactly: the
/// sum of every member's live balance, priced live -- not the indexer's synced copy, since the
/// curve itself reads `balanceOf` at quote time and this needs to agree with it. Undefined if any
/// single member's price is stale or missing, the same way the on-chain oracle read would fail --
/// one bad feed makes the whole group's value (and so every leg touching it) unusable, not just
/// that one member.
async function groupValueWad(
  db: Db,
  publicClient: PublicClient,
  maker: Address,
  group: DecodedGroup,
  nowSeconds: bigint,
  maxPriceStalenessSeconds: bigint,
): Promise<bigint | undefined> {
  let total = 0n;
  for (const member of group.members) {
    const [price, decimals, balance] = await Promise.all([
      readUsablePrice(db, member.feed, nowSeconds, maxPriceStalenessSeconds),
      tokenDecimals(publicClient, member.token),
      tokenBalance(publicClient, member.token, maker),
    ]);
    if (!price) return undefined;
    total += valueWad(balance, price.priceWad, decimals);
  }
  return total;
}

export interface CandidateEvaluationConfig {
  minTradeUsdWad: bigint;
  maxTradeUsdWad: bigint;
  minProfitUsdWad: bigint;
  maxPriceStalenessSeconds: bigint;
  fyndSlippageBps: bigint;
  fyndMinResponses: number;
  fyndTimeoutMs: number;
  slippageBufferBps: bigint;
  deadlineBufferSeconds: number;
  arbitrageurAddress: Address;
}

interface Opportunity {
  amountIn: bigint;
  quotedOut: bigint;
  fairOut: bigint;
  profitBps: bigint;
  profitUsdWad: bigint;
}

/// Candidate Evaluation domain: for one Strategy at one State Version, prices every cross-group
/// leg with Balancer's closed-form "In-Given-Price" formula (see pricing.ts's own doc comment --
/// adapted here for this curve's group-level, fee-inclusive pricing) instead of searching a range
/// of candidate sizes: the formula gives the exact trade value that would bring the two groups to
/// equilibrium directly, so each leg costs exactly one real `quoteExactIn` verification, not the
/// dozen a geometric-step search over candidate sizes used to need. Then gets a real Fynd quote
/// only for the leg that passed, and ranks by
/// Profit Headroom (ADR-0014's own metric: the real route's expected return, less principal, less
/// the return-token value of the Profit Floor). Returns undefined when nothing clears the bar --
/// callers should not enqueue a simulate-candidate job in that case.
export async function evaluateStrategy(
  db: Db,
  publicClient: PublicClient,
  account: ReturnType<typeof privateKeyToAccount>,
  fyndClient: FyndClient,
  strategyId: string,
  stateVersion: string,
  retryCount: number,
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
  const maker = order.maker;

  // The curve's own fee, on the same WAD scale as the formula -- feeBps is PM's own PM_BPS (1e9)
  // convention (see PortfolioManagerArgsCodec.sol's PM_BPS), matching
  // PortfolioManagerSwap.sol's `feeWad: FixedPointMath.divDown(feeBps, PM_BPS)` exactly.
  const feeWad = (BigInt(decoded.feeBps) * WAD) / 1_000_000_000n;

  // Computed lazily, once per group, and reused across every leg that touches it -- the trade
  // value the formula gives is the same for every member pair within one group pair.
  const groupValueCache = new Map<number, bigint | undefined>();
  async function cachedGroupValueWad(groupIdx: number): Promise<bigint | undefined> {
    if (!groupValueCache.has(groupIdx)) {
      groupValueCache.set(
        groupIdx,
        await groupValueWad(db, publicClient, maker, decoded.groups[groupIdx]!, nowSeconds, config.maxPriceStalenessSeconds),
      );
    }
    return groupValueCache.get(groupIdx);
  }

  let best: { leg: Leg; opportunity: Opportunity } | undefined;
  for (const leg of legs) {
    const [groupInValueWad, groupOutValueWad] = await Promise.all([
      cachedGroupValueWad(leg.groupInIdx),
      cachedGroupValueWad(leg.groupOutIdx),
    ]);
    if (groupInValueWad === undefined || groupOutValueWad === undefined) continue; // a member's feed is stale

    const tradeValueWad = inGivenPriceValueWad({
      groupInValueWad,
      groupOutValueWad,
      weightInWad: decoded.groups[leg.groupInIdx]!.weightWad,
      weightOutWad: decoded.groups[leg.groupOutIdx]!.weightWad,
      feeWad,
    });
    if (tradeValueWad <= 0n) continue; // this direction moves the price further from equilibrium
    if (tradeValueWad < config.minTradeUsdWad) continue; // analytic optimum too small to be worth a quote and gas
    const clampedValueWad = tradeValueWad > config.maxTradeUsdWad ? config.maxTradeUsdWad : tradeValueWad;

    const [priceIn, priceOut] = await Promise.all([
      readUsablePrice(db, leg.feedIn, nowSeconds, config.maxPriceStalenessSeconds),
      readUsablePrice(db, leg.feedOut, nowSeconds, config.maxPriceStalenessSeconds),
    ]);
    if (!priceIn || !priceOut) continue; // one bad/missing feed skips only this leg

    const [decimalsIn, decimalsOut] = await Promise.all([
      tokenDecimals(publicClient, leg.tokenIn),
      tokenDecimals(publicClient, leg.tokenOut),
    ]);

    const amountIn = amountForUsdWad(clampedValueWad, priceIn.priceWad, decimalsIn);
    const quotedOut = await quoteExactIn(publicClient, account, config.arbitrageurAddress, order, leg.tokenIn, leg.tokenOut, amountIn);
    const fairOut = fairAmountOut(amountIn, priceIn.priceWad, decimalsIn, priceOut.priceWad, decimalsOut);
    const usdProfit = profitUsdWad(quotedOut, fairOut, priceOut.priceWad, decimalsOut);
    if (usdProfit < config.minProfitUsdWad) continue;

    const opportunity: Opportunity = { amountIn, quotedOut, fairOut, profitBps: profitBps(quotedOut, fairOut), profitUsdWad: usdProfit };
    if (!best || opportunity.profitUsdWad > best.opportunity.profitUsdWad) {
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
  // retryCount is part of the id, not just a column: maybeRetry re-enqueues evaluation under the
  // same stateVersion, only incrementing retryCount, so omitting it here would make a retry's
  // fresh amountIn/quotedOut/fyndCalldata/deadline silently lost to onConflictDoNothing below,
  // leaving simulate-candidate re-simulating the original (likely now-stale) attempt forever.
  const candidateId = `${strategyId}-${leg.tokenIn}-${leg.tokenOut}-${stateVersion}-${retryCount}`;

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
      retryCount,
      status: "eligible",
    })
    .onConflictDoNothing();

  return candidateId;
}
