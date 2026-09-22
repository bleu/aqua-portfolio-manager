import { loadConfig, type Config, type Order, type TokenFeed } from "./config.js";
import { makeClients, tokenDecimals, quoteExactIn, executeFlashArbitrage } from "./chain.js";
import { readOraclePriceWad } from "./oracle.js";
import { findBestOpportunity, type Opportunity } from "./pricing.js";
import { getFyndSwapCalldata } from "./fynd.js";

const ORACLE_MAX_STALENESS_SECONDS = 12 * 60 * 60; // matches PortfolioManagerE2EBase's own PM_MAX_STALENESS default

interface Leg {
  tokenIn: `0x${string}`;
  tokenOut: `0x${string}`;
  feedIn: `0x${string}`;
  feedOut: `0x${string}`;
}

/// Every directed cross-group pair: each member of `groupA` traded against each member of
/// `groupB`, both directions -- the PM curve only ever prices a trade between two *different*
/// declared groups (`PortfolioManagerSwap._resolve`'s `groupInIdx != groupOutIdx` check), never
/// within one, so within-group pairs are never legs here.
function buildLegs(groupA: TokenFeed[], groupB: TokenFeed[]): Leg[] {
  const legs: Leg[] = [];
  for (const a of groupA) {
    for (const b of groupB) {
      legs.push({ tokenIn: a.token, tokenOut: b.token, feedIn: a.feed, feedOut: b.feed });
      legs.push({ tokenIn: b.token, tokenOut: a.token, feedIn: b.feed, feedOut: a.feed });
    }
  }
  return legs;
}

async function findBestAcrossAllLegs(
  config: Config,
  clients: ReturnType<typeof makeClients>,
  order: Order,
  legs: Leg[],
  decimals: Map<string, number>,
): Promise<{ leg: Leg; opportunity: Opportunity } | undefined> {
  let best: { leg: Leg; opportunity: Opportunity } | undefined;

  for (const leg of legs) {
    const [priceInWad, priceOutWad] = await Promise.all([
      readOraclePriceWad(clients.publicClient, leg.feedIn, ORACLE_MAX_STALENESS_SECONDS),
      readOraclePriceWad(clients.publicClient, leg.feedOut, ORACLE_MAX_STALENESS_SECONDS),
    ]);

    const opportunity = await findBestOpportunity({
      minAmount: config.minTradeAmount,
      maxAmount: config.maxTradeAmount,
      steps: config.searchSteps,
      minProfitBps: config.minProfitBps,
      priceInWad,
      decimalsIn: decimals.get(leg.tokenIn)!,
      priceOutWad,
      decimalsOut: decimals.get(leg.tokenOut)!,
      quote: (amountIn) =>
        quoteExactIn(clients.publicClient, config.arbitrageurAddress, order, leg.tokenIn, leg.tokenOut, amountIn),
    });

    if (opportunity && (!best || opportunity.profitBps > best.opportunity.profitBps)) {
      best = { leg, opportunity };
    }
  }

  return best;
}

async function tick(config: Config, clients: ReturnType<typeof makeClients>, legs: Leg[], decimals: Map<string, number>) {
  const best = await findBestAcrossAllLegs(config, clients, config.order, legs, decimals);

  if (!best) {
    console.log(`[${new Date().toISOString()}] no opportunity above ${config.minProfitBps}bps`);
    return;
  }

  const { leg, opportunity } = best;
  console.log(
    `[${new Date().toISOString()}] opportunity: ${opportunity.amountIn} ${leg.tokenIn} -> ` +
      `${opportunity.quotedOut} ${leg.tokenOut} (fair=${opportunity.fairOut}, profit=${opportunity.profitBps}bps)`,
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
  const fyndQuote = await getFyndSwapCalldata({
    fyndUrl: config.fyndUrl,
    chain: config.fyndChain,
    tokenIn: leg.tokenOut,
    tokenOut: leg.tokenIn,
    amountIn: minCurveAmountOut,
    sender: config.arbitrageurAddress,
    slippageBps: config.fyndSlippageBps,
  });

  const result = await executeFlashArbitrage(clients, config.arbitrageurAddress, {
    order: config.order,
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

  const legs = buildLegs(config.groupA, config.groupB);
  const allTokens = [...config.groupA, ...config.groupB].map((t) => t.token);

  const decimals = new Map<string, number>(
    await Promise.all(allTokens.map(async (token) => [token, await tokenDecimals(clients.publicClient, token)] as const)),
  );

  console.log(
    `arbitrageur watching ${legs.length} cross-group legs via ${config.arbitrageurAddress} ` +
      `(fynd=${config.fyndUrl}, dryRun=${config.dryRun}, pollIntervalMs=${config.pollIntervalMs})`,
  );

  let stopped = false;
  const stop = () => {
    stopped = true;
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);

  while (!stopped) {
    try {
      await tick(config, clients, legs, decimals);
    } catch (err) {
      console.error(`tick failed: ${err instanceof Error ? err.message : err}`);
    }
    await new Promise((resolve) => setTimeout(resolve, config.pollIntervalMs));
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
