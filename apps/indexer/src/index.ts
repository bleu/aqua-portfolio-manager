import { ponder } from "ponder:registry";
import {
  chainlinkAggregatorFeed,
  priceSnapshot,
  strategy,
  strategyAttestation,
  strategyWallet,
  walletBalanceChange,
} from "ponder:schema";
import { erc20Abi, type Address, type Hex } from "viem";
import { SEED_AGGREGATOR_TO_PROXY } from "@aqua-portfolio-manager/addresses";

/// This deployment's own Portfolio Manager Router (packages/contracts/broadcast/Deploy.s.sol/
/// 8453/run-latest.json -- the real, current deployment, not ShipStrategy.s.sol's old ROUTER
/// constant from an earlier test deployment) -- the balance seed below only ever runs for
/// strategies shipped through this specific app, never for another app's strategy sharing the
/// same Aqua registry.
const PM_ROUTER = "0x672b64e36152162c1fec42225d33bbb15520231a";

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

  // Marks the maker as a known Strategy Wallet so the Transfer handler below can decide in O(1)
  // whether a transfer is balance-relevant. Idempotent on purpose: re-inserted on every Shipped
  // event from the same maker, safe since the row only ever holds the address itself.
  await context.db.insert(strategyWallet).values({ address: maker }).onConflictDoNothing();
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

  // Balance seed: only for this deployment's own PM Router, and only once per token, right here
  // at shipping -- never for another app's strategy, and never again on a later trade-time Pushed
  // (excluded above by the shippedAtTxHash check). A wallet's tokens funded into the Safe
  // *before* shipping (the normal case) are otherwise invisible: WalletBalanceChange only carries
  // deltas, with nothing to seed the running sum, so this fills exactly that gap with one real
  // balanceOf read.
  if (app === PM_ROUTER) {
    const balance = await context.client.readContract({
      address: token,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [maker],
      blockNumber: event.block.number,
    });
    await context.db
      .insert(walletBalanceChange)
      .values({
        id: `${event.transaction.hash}-seed-${token}`,
        wallet: maker,
        token,
        // Synthetic, not a real Transfer's delta -- the wallet's whole balance as of this block,
        // applied as one lump delta onto a starting sum of zero so apps/arbitrageur's existing
        // accumulation (`balance = balance + delta`) needs no change to consume it. Always the
        // first row for this wallet+token (shipping is the very first block this token could
        // have become balance-relevant), so this ordering is safe.
        change: balance,
        blockNumber: event.block.number,
        blockTimestamp: event.block.timestamp,
        transactionHash: event.transaction.hash,
        logIndex: -1, // sorts before the shipping transaction's own real logIndex-0-or-later rows
      })
      .onConflictDoNothing();
  }
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

ponder.on("ERC20:Transfer", async ({ event, context }) => {
  const from = event.args.from.toLowerCase() as Address;
  const to = event.args.to.toLowerCase() as Address;

  // Most Transfers on these tokens have nothing to do with a Strategy Wallet -- filtered here,
  // not at the config source, since the wallet set is only known from already-indexed Strategy
  // data (see ponder.config.ts's ERC20 contract comment).
  const [fromWallet, toWallet] = await Promise.all([
    context.db.find(strategyWallet, { address: from }),
    context.db.find(strategyWallet, { address: to }),
  ]);
  if (fromWallet === null && toWallet === null) return;

  const base = {
    token: event.log.address.toLowerCase() as Address,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
    transactionHash: event.transaction.hash,
    logIndex: event.log.logIndex,
  };
  // Suffixed, not shared, IDs: a self-transfer (from === to) would otherwise collide on the same
  // transactionHash-logIndex row and silently drop one side's balance change.
  if (fromWallet !== null) {
    await context.db
      .insert(walletBalanceChange)
      .values({ id: `${event.transaction.hash}-${event.log.logIndex}-out`, wallet: from, change: -event.args.value, ...base })
      .onConflictDoNothing();
  }
  if (toWallet !== null) {
    await context.db
      .insert(walletBalanceChange)
      .values({ id: `${event.transaction.hash}-${event.log.logIndex}-in`, wallet: to, change: event.args.value, ...base })
      .onConflictDoNothing();
  }
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
