import { formatUnits } from "viem";
import { loadConfig, type Config, type Order, type Strategy } from "./config.js";
import { makeClients, tokenDecimals, quoteExactIn, executeFlashArbitrage } from "./chain.js";
import { readOraclePriceWad } from "./oracle.js";
import { findBestOpportunity, type Opportunity } from "./pricing.js";
import { getFyndSwapCalldata, FyndClient } from "./fynd.js";

const ORACLE_MAX_STALENESS_SECONDS = 12 * 60 * 60; // matches PortfolioManagerE2EBase's own PM_MAX_STALENESS default

interface Leg {
  order: Order;
  tokenIn: `0x${string}`;
  tokenOut: `0x${string}`;
  feedIn: `0x${string}`;
  feedOut: `0x${string}`;
}

/// Every directed cross-group pair within one strategy: each member of `groupA` traded against
/// each member of `groupB`, both directions -- the PM curve only ever prices a trade between two
/// *different* declared groups (`PortfolioManagerSwap._resolve`'s `groupInIdx != groupOutIdx`
/// check), never within one, so within-group pairs are never legs here.
function buildLegsForStrategy({ order, groupA, groupB }: Strategy): Leg[] {
  const legs: Leg[] = [];
  for (const a of groupA) {
    for (const b of groupB) {
      legs.push({ order, tokenIn: a.token, tokenOut: b.token, feedIn: a.feed, feedOut: b.feed });
      legs.push({ order, tokenIn: b.token, tokenOut: a.token, feedIn: b.feed, feedOut: a.feed });
    }
  }
  return legs;
}

/// Every leg across every declared strategy -- searched together each tick so the single most
/// profitable opportunity wins regardless of which strategy it came from (see
/// `findBestAcrossAllLegs`). Ready to watch as many strategies as `STRATEGIES_FILE` declares;
/// discovering that list dynamically from an indexer instead of a static file is a separate,
/// larger piece of work (see this package's README).
function buildLegs(strategies: Strategy[]): Leg[] {
  return strategies.flatMap(buildLegsForStrategy);
}

async function findBestAcrossAllLegs(
  config: Config,
  clients: ReturnType<typeof makeClients>,
  legs: Leg[],
  decimals: Map<string, number>,
): Promise<{ leg: Leg; opportunity: Opportunity } | undefined> {
  // Each feed backs multiple legs (every token appears as feedIn in one direction and feedOut in
  // the reverse, and can recur across several legs in a basket) -- read every distinct feed once
  // per tick instead of once per leg-occurrence.
  const uniqueFeeds = [...new Set(legs.flatMap((leg) => [leg.feedIn, leg.feedOut]))];
  const priceEntries = await Promise.all(
    uniqueFeeds.map(
      async (feed) => [feed, await readOraclePriceWad(clients.publicClient, feed, ORACLE_MAX_STALENESS_SECONDS)] as const,
    ),
  );
  const prices = new Map(priceEntries);

  // Legs are independent read-only work (an oracle-price lookup plus a curve-quote search) --
  // evaluated concurrently rather than one leg at a time.
  const results = await Promise.all(
    legs.map(async (leg) => {
      const opportunity = await findBestOpportunity({
        minAmount: config.minTradeAmount,
        maxAmount: config.maxTradeAmount,
        steps: config.searchSteps,
        minProfitUsdWad: config.minProfitUsdWad,
        priceInWad: prices.get(leg.feedIn)!,
        decimalsIn: decimals.get(leg.tokenIn)!,
        priceOutWad: prices.get(leg.feedOut)!,
        decimalsOut: decimals.get(leg.tokenOut)!,
        quote: (amountIn) =>
          quoteExactIn(clients.publicClient, config.arbitrageurAddress, leg.order, leg.tokenIn, leg.tokenOut, amountIn),
      });
      return opportunity ? { leg, opportunity } : undefined;
    }),
  );

  let best: { leg: Leg; opportunity: Opportunity } | undefined;
  for (const result of results) {
    if (result && (!best || result.opportunity.profitBps > best.opportunity.profitBps)) {
      best = result;
    }
  }

  return best;
}

async function tick(
  config: Config,
  clients: ReturnType<typeof makeClients>,
  fyndClient: FyndClient,
  legs: Leg[],
  decimals: Map<string, number>,
) {
  const best = await findBestAcrossAllLegs(config, clients, legs, decimals);

  if (!best) {
    console.log(`[${new Date().toISOString()}] no opportunity above $${formatUnits(config.minProfitUsdWad, 18)}`);
    return;
  }

  const { leg, opportunity } = best;
  console.log(
    `[${new Date().toISOString()}] opportunity: ${opportunity.amountIn} ${leg.tokenIn} -> ` +
      `${opportunity.quotedOut} ${leg.tokenOut} (fair=${opportunity.fairOut}, ` +
      `profit=$${formatUnits(opportunity.profitUsdWad, 18)} / ${opportunity.profitBps}bps)`,
  );

  if (config.dryRun) {
    console.log("DRY_RUN=true -- not executing");
    return;
  }

  const minCurveAmountOut =
    opportunity.quotedOut - (opportunity.quotedOut * config.slippageBufferBps) / 10_000n;
  const deadline = Math.floor(Date.now() / 1000) + config.deadlineBufferSeconds;

  // The return leg: sell the curve's tokenOut proceeds back into tokenIn (the borrowed token),
  // via whatever route Fynd finds. `sender` is the Arbitrageur contract itself -- it's the
  // account that will actually hold and spend tokenOut mid-flash-loan, not this server's EOA.
  // Sized off the actual expected curve output, not `minCurveAmountOut` -- that's a slippage
  // floor for the curve leg's own on-chain check, not how much this leg should trade; sizing
  // the Fynd request off the floor would leave the gap between it and the real payout stranded
  // on the contract every time the curve leg doesn't actually slip.
  const fyndQuote = await getFyndSwapCalldata(fyndClient, {
    tokenIn: leg.tokenOut,
    tokenOut: leg.tokenIn,
    amountIn: opportunity.quotedOut,
    sender: config.arbitrageurAddress,
    slippageBps: config.fyndSlippageBps,
  });

  const result = await executeFlashArbitrage(clients, config.arbitrageurAddress, {
    order: leg.order,
    tokenIn: leg.tokenIn,
    tokenOut: leg.tokenOut,
    amountIn: opportunity.amountIn,
    minCurveAmountOut,
    fyndTarget: fyndQuote.target,
    fyndSpender: fyndQuote.spender,
    fyndCalldata: fyndQuote.calldata,
    deadline,
  });

  console.log(`executed: tx=${result.txHash}`);
}

async function main() {
  const config = loadConfig();
  const clients = makeClients(config);
  // One long-lived client per process rather than one per tick -- it holds no per-request
  // state, so there's nothing to gain from rebuilding it.
  const fyndClient = new FyndClient({
    baseUrl: config.fyndUrl,
    chain: config.fyndChain,
    timeoutMs: config.deadlineBufferSeconds * 1000,
  });

  const legs = buildLegs(config.strategies);
  // A token can recur across strategies (e.g. the same USDC in two different baskets) -- collect
  // its decimals once, not once per strategy it appears in.
  const allTokens = [
    ...new Set(config.strategies.flatMap((s) => [...s.groupA, ...s.groupB]).map((t) => t.token)),
  ];

  const decimals = new Map<string, number>(
    await Promise.all(allTokens.map(async (token) => [token, await tokenDecimals(clients.publicClient, token)] as const)),
  );

  console.log(
    `arbitrageur watching ${legs.length} cross-group legs across ${config.strategies.length} ` +
      `strategies via ${config.arbitrageurAddress} (fynd=${config.fyndUrl}, dryRun=${config.dryRun}, ` +
      `blockPollingIntervalMs=${config.blockPollingIntervalMs})`,
  );

  // Runs on every new block instead of a fixed timer, so a tick never fires on a block it's
  // already seen. `ticking` skips a block if the previous tick is still in flight (e.g. waiting
  // on a transaction receipt), rather than starting a second tick that would race the same
  // nonce/allowance state -- the next block retries.
  let ticking = false;
  const unwatch = clients.publicClient.watchBlocks({
    pollingInterval: config.blockPollingIntervalMs,
    onBlock: () => {
      if (ticking) return;
      ticking = true;
      tick(config, clients, fyndClient, legs, decimals)
        .catch((err) => console.error(`tick failed: ${err instanceof Error ? err.message : err}`))
        .finally(() => {
          ticking = false;
        });
    },
  });

  const stop = () => {
    unwatch();
    process.exit(0);
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
