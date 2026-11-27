import { ponder } from "ponder:registry";
import { chainlinkAggregatorFeed, priceSnapshot, strategy, strategyAttestation } from "ponder:schema";
import type { Address, Hex } from "viem";
import { SEED_AGGREGATOR_TO_PROXY } from "@aqua-portfolio-manager/addresses";

function strategyId(maker: string, app: string, strategyHash: string): string {
  return `${maker}-${app}-${strategyHash}`.toLowerCase();
}

ponder.on("PortfolioManagerValidator:BuildParametersAttested", async ({ event, context }) => {
  const groupNames = [...event.args.groupNames];
  await context.db
    .insert(strategyAttestation)
    .values({ strategyHash: event.args.strategyHash.toLowerCase() as Hex, groupNames })
    .onConflictDoUpdate({ groupNames });
});

ponder.on("Aqua:Shipped", async ({ event, context }) => {
  const maker = event.args.maker.toLowerCase() as Address;
  const app = event.args.app.toLowerCase() as Address;
  const strategyHash = event.args.strategyHash.toLowerCase() as Hex;
  const id = strategyId(maker, app, strategyHash);

  // ShipStrategy.s.sol always batches attest then ship in the same transaction, so a same-block
  // attestation is already indexed by the time this handler runs. A strategy shipped without
  // ever attesting (or attesting with an empty groupNames) simply has no row here.
  const attestation = await context.db.find(strategyAttestation, { strategyHash });

  const row = {
    id,
    maker,
    app,
    strategyHash,
    encodedOrder: event.args.strategy,
    tokens: [] as Address[], // filled in as this same transaction's Pushed events arrive, below
    isActive: true,
    shippedAt: event.block.timestamp,
    shippedAtTxHash: event.transaction.hash,
    dockedAt: null,
    dockedAtTxHash: null,
    groupNames: attestation && attestation.groupNames.length > 0 ? attestation.groupNames : null,
  };
  await context.db.insert(strategy).values(row).onConflictDoUpdate(row);
});

ponder.on("Aqua:Pushed", async ({ event, context }) => {
  const maker = event.args.maker.toLowerCase() as Address;
  const app = event.args.app.toLowerCase() as Address;
  const strategyHash = event.args.strategyHash.toLowerCase() as Hex;
  const id = strategyId(maker, app, strategyHash);

  // Ignore pushes for strategies shipped before the indexed range.
  const existing = await context.db.find(strategy, { id });
  if (existing === null) return;
  // Only pushes in the shipping transaction declare the token universe.
  if (existing.shippedAtTxHash !== event.transaction.hash) return;

  const token = event.args.token.toLowerCase() as Address;
  if (existing.tokens.includes(token)) return;
  await context.db.update(strategy, { id }).set({ tokens: [...existing.tokens, token] });
});

ponder.on("Aqua:Docked", async ({ event, context }) => {
  const maker = event.args.maker.toLowerCase() as Address;
  const app = event.args.app.toLowerCase() as Address;
  const strategyHash = event.args.strategyHash.toLowerCase() as Hex;
  const id = strategyId(maker, app, strategyHash);

  // Fail on an unknown docked strategy so missing shipping history is visible.
  const existing = await context.db.find(strategy, { id });
  if (existing === null) {
    throw new Error(`Docked for unknown strategy ${id}`);
  }
  await context.db
    .update(strategy, { id })
    .set({ isActive: false, dockedAt: event.block.timestamp, dockedAtTxHash: event.transaction.hash });
});

// Records which feed a newly-confirmed aggregator belongs to, keyed by the aggregator's own
// address. The dynamic watching itself (so AnswerUpdated handlers below actually fire for this
// new address) is config-level, via ponder.config.ts's ChainlinkAggregatorDynamic factory --
// nothing to register here beyond this mapping row.
ponder.on("ChainlinkProxy:AggregatorConfirmed", async ({ event, context }) => {
  const feedProxy = event.log.address.toLowerCase() as Address;
  await context.db
    .insert(chainlinkAggregatorFeed)
    .values({ aggregator: event.args.latest.toLowerCase() as Address, feedProxy })
    .onConflictDoUpdate({ feedProxy });
});

// Shared by both ChainlinkAggregatorSeed (the known aggregator per feed as of setup) and
// ChainlinkAggregatorDynamic (every aggregator a feed proxy swaps to afterward) -- same event,
// same handling, just two different ways of discovering which addresses to watch it on.
async function handleAnswerUpdated({
  event,
  context,
}: Parameters<Parameters<typeof ponder.on<"ChainlinkAggregatorSeed:AnswerUpdated">>[1]>[0]) {
  const aggregator = event.log.address.toLowerCase() as Address;
  const mapping = await context.db.find(chainlinkAggregatorFeed, { aggregator });
  const feedProxy = mapping?.feedProxy ?? SEED_AGGREGATOR_TO_PROXY[aggregator];
  // Every address ChainlinkAggregator{Seed,Dynamic} ever watches comes from the seed list or
  // from the AggregatorConfirmed handler above, both of which have a known feed -- this should
  // be unreachable, but fail loudly rather than write an orphaned PriceSnapshot if it isn't.
  if (feedProxy === undefined) {
    throw new Error(`ChainlinkAggregator ${aggregator} has no known feed`);
  }
  await context.db
    .insert(priceSnapshot)
    .values({
      id: `${event.transaction.hash}-${event.log.logIndex}`,
      feedProxy: feedProxy as Address,
      answer: event.args.current,
      updatedAt: event.args.updatedAt,
      blockNumber: event.block.number,
      blockTimestamp: event.block.timestamp,
      transactionHash: event.transaction.hash,
      logIndex: event.log.logIndex,
    })
    .onConflictDoNothing();
}

ponder.on("ChainlinkAggregatorSeed:AnswerUpdated", handleAnswerUpdated);
ponder.on("ChainlinkAggregatorDynamic:AnswerUpdated", handleAnswerUpdated);
