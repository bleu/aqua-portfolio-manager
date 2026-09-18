import { loadConfig, type Order } from "./config.js";
import { makeClients, tokenDecimals, quoteExactIn, executeArbitrage, ensureAllowance } from "./chain.js";
import { readOraclePriceWad } from "./oracle.js";
import { findBestOpportunity, type Opportunity } from "./pricing.js";

const ORACLE_MAX_STALENESS_SECONDS = 12 * 60 * 60; // matches PortfolioManagerE2EBase's own PM_MAX_STALENESS default

interface Leg {
  tokenIn: `0x${string}`;
  tokenOut: `0x${string}`;
  feedIn: `0x${string}`;
  feedOut: `0x${string}`;
}

async function findBestAcrossBothDirections(
  config: ReturnType<typeof loadConfig>,
  clients: ReturnType<typeof makeClients>,
  order: Order,
  legs: [Leg, Leg],
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

async function tick(config: ReturnType<typeof loadConfig>, clients: ReturnType<typeof makeClients>, legs: [Leg, Leg], decimals: Map<string, number>) {
  const best = await findBestAcrossBothDirections(config, clients, config.order, legs, decimals);

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

  const minAmountOut =
    opportunity.quotedOut - (opportunity.quotedOut * config.slippageBufferBps) / 10_000n;
  const deadline = Math.floor(Date.now() / 1000) + config.deadlineBufferSeconds;

  await ensureAllowance(clients, leg.tokenIn, config.arbitrageurAddress, opportunity.amountIn);
  const result = await executeArbitrage(
    clients,
    config.arbitrageurAddress,
    config.order,
    leg.tokenIn,
    leg.tokenOut,
    opportunity.amountIn,
    minAmountOut,
    deadline,
  );

  console.log(`executed: tx=${result.txHash} amountOut=${result.amountOut}`);
}

async function main() {
  const config = loadConfig();
  const clients = makeClients(config);

  const legs: [Leg, Leg] = [
    { tokenIn: config.tokenIn, tokenOut: config.tokenOut, feedIn: config.feedIn, feedOut: config.feedOut },
    { tokenIn: config.tokenOut, tokenOut: config.tokenIn, feedIn: config.feedOut, feedOut: config.feedIn },
  ];

  const decimals = new Map<string, number>([
    [config.tokenIn, await tokenDecimals(clients.publicClient, config.tokenIn)],
    [config.tokenOut, await tokenDecimals(clients.publicClient, config.tokenOut)],
  ]);

  console.log(
    `arbitrageur watching ${config.tokenIn} <-> ${config.tokenOut} via ${config.arbitrageurAddress} ` +
      `(dryRun=${config.dryRun}, pollIntervalMs=${config.pollIntervalMs})`,
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
