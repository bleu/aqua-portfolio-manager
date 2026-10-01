import { indexer, createEffect, S } from "envio";
import { createPublicClient, http, erc20Abi, type Address } from "viem";
import { SEED_AGGREGATOR_TO_PROXY } from "./generated/baseMainnetAddresses.js";

function strategyId(maker: string, app: string, strategyHash: string): string {
  return `${maker}-${app}-${strategyHash}`.toLowerCase();
}

/// This deployment's own Portfolio Manager Router (packages/contracts/script/Deploy.s.sol's
/// broadcast receipt on Base) -- the balance seed below only ever runs for strategies shipped
/// through this specific app, never for another app's strategy sharing the same Aqua registry.
const PM_ROUTER = "0x02a11927b0a1c701feb589ca86886f4ae1f85f02";

const publicClient = createPublicClient({
  transport: http(process.env.BASE_RPC_URL ?? "https://mainnet.base.org"),
});

/// A wallet's balance for a PM strategy's declared token, at the moment it was shipped.
/// Balance State (ADR-0014) only ever sees a Transfer once its wallet is already a known Strategy
/// Wallet -- so tokens funded into the Safe *before* shipping (the normal case) are otherwise
/// invisible: WalletBalanceChange only carries deltas, with nothing to seed the running sum. This
/// effect fills exactly that gap with one real `balanceOf` read, cached so a rerun never repeats
/// it (see the Pushed handler below for where and how often this actually runs).
const getErc20Balance = createEffect(
  {
    name: "getErc20Balance",
    input: { token: S.string, wallet: S.string, blockNumber: S.bigint },
    output: S.bigint,
    rateLimit: { calls: 5, per: "second" },
    cache: true,
  },
  async ({ input }) => {
    return publicClient.readContract({
      address: input.token as Address,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [input.wallet as Address],
      blockNumber: input.blockNumber,
    });
  },
);

indexer.onEvent({ contract: "Aqua", event: "Shipped" }, async ({ event, context }) => {
  const id = strategyId(event.params.maker, event.params.app, event.params.strategyHash);
  context.Strategy.set({
    id,
    maker: event.params.maker,
    app: event.params.app,
    strategyHash: event.params.strategyHash,
    encodedOrder: event.params.strategy,
    tokens: [], // filled in as this same transaction's Pushed events arrive, below
    isActive: true,
    shippedAt: BigInt(event.block.timestamp),
    shippedAtTxHash: event.transaction.hash,
    dockedAt: undefined,
    dockedAtTxHash: undefined,
  });
  // Marks the maker as a known Strategy Wallet so the Transfer handler below can decide in O(1)
  // whether a transfer is balance-relevant. Idempotent: re-set on every Shipped event from the
  // same maker, safe since the row only ever holds the address itself.
  context.StrategyWallet.set({ id: event.params.maker.toLowerCase() });
});

indexer.onEvent({ contract: "Aqua", event: "Pushed" }, async ({ event, context }) => {
  const id = strategyId(event.params.maker, event.params.app, event.params.strategyHash);
  const strategy = await context.Strategy.get(id);
  // Ignore pushes for strategies shipped before the indexed range.
  if (strategy === undefined) return;
  // Only pushes in the shipping transaction declare the token universe.
  if (strategy.shippedAtTxHash !== event.transaction.hash) return;
  if (strategy.tokens.includes(event.params.token)) return;
  context.Strategy.set({ ...strategy, tokens: [...strategy.tokens, event.params.token] });

  // Balance seed: only for this deployment's own PM Router, and only once per token, right here
  // at shipping -- never for another app's strategy, and never again on a later trade-time Pushed
  // (excluded above by the shippedAtTxHash check). See getErc20Balance's own doc comment for why
  // this is needed at all.
  if (event.params.app.toLowerCase() === PM_ROUTER) {
    const balance = await context.effect(getErc20Balance, {
      token: event.params.token,
      wallet: event.params.maker,
      blockNumber: BigInt(event.block.number),
    });
    context.WalletBalanceChange.set({
      id: `${event.transaction.hash}-seed-${event.params.token.toLowerCase()}`,
      wallet: event.params.maker.toLowerCase(),
      token: event.params.token,
      // Synthetic, not a real Transfer's delta -- the wallet's whole balance as of this block,
      // applied as one lump delta onto a starting sum of zero so the existing accumulation in
      // apps/arbitrageur's syncWalletBalanceChanges (`balance = balance + delta`) needs no
      // change to consume it. Always the first row for this wallet+token (shipping is the very
      // first block this token could have become balance-relevant), so this ordering is safe.
      change: balance,
      blockNumber: BigInt(event.block.number),
      blockTimestamp: BigInt(event.block.timestamp),
      transactionHash: event.transaction.hash,
      logIndex: -1, // sorts before the shipping transaction's own real logIndex-0-or-later rows
    });
  }
});

indexer.onEvent({ contract: "Aqua", event: "Docked" }, async ({ event, context }) => {
  const id = strategyId(event.params.maker, event.params.app, event.params.strategyHash);
  // Fail on an unknown docked strategy so missing shipping history is visible.
  const strategy = await context.Strategy.getOrThrow(id);
  context.Strategy.set({
    ...strategy,
    isActive: false,
    dockedAt: BigInt(event.block.timestamp),
    dockedAtTxHash: event.transaction.hash,
  });
});

indexer.onEvent({ contract: "ERC20", event: "Transfer" }, async ({ event, context }) => {
  const from = event.params.from.toLowerCase();
  const to = event.params.to.toLowerCase();
  // Most Transfers on these tokens have nothing to do with a Strategy Wallet -- filtered here,
  // not at the config.yaml source, since the wallet set is only known from already-indexed
  // Strategy data (see config.yaml's ERC20 contract comment).
  const [fromWallet, toWallet] = await Promise.all([
    context.StrategyWallet.get(from),
    context.StrategyWallet.get(to),
  ]);
  if (fromWallet === undefined && toWallet === undefined) return;

  const base = {
    token: event.srcAddress,
    blockNumber: BigInt(event.block.number),
    blockTimestamp: BigInt(event.block.timestamp),
    transactionHash: event.transaction.hash,
    logIndex: event.logIndex,
  };
  // Suffixed, not shared, IDs: a self-transfer (from === to) would otherwise collide on the
  // same transactionHash-logIndex row and silently drop one side's balance change.
  if (fromWallet !== undefined) {
    context.WalletBalanceChange.set({
      id: `${event.transaction.hash}-${event.logIndex}-out`,
      wallet: from,
      change: -event.params.value,
      ...base,
    });
  }
  if (toWallet !== undefined) {
    context.WalletBalanceChange.set({
      id: `${event.transaction.hash}-${event.logIndex}-in`,
      wallet: to,
      change: event.params.value,
      ...base,
    });
  }
});

// Follows each feed proxy's live aggregator so ChainlinkAggregator's address set never goes
// stale after Chainlink swaps one -- see config.yaml's ChainlinkAggregator comment.
indexer.contractRegister({ contract: "ChainlinkProxy", event: "AggregatorConfirmed" }, async ({ event, context }) => {
  context.chain.ChainlinkAggregator.add(event.params.latest);
});

// Records which feed a newly-confirmed aggregator belongs to, keyed by the aggregator's own
// address, so the AnswerUpdated handler below can recover the feed identity that event alone
// doesn't carry. Runs alongside, not instead of, the contractRegister handler above -- one adds
// the address to watch, this one records what it means.
indexer.onEvent({ contract: "ChainlinkProxy", event: "AggregatorConfirmed" }, async ({ event, context }) => {
  context.ChainlinkAggregatorFeed.set({
    id: event.params.latest.toLowerCase(),
    feedProxy: event.srcAddress.toLowerCase(),
  });
});

indexer.onEvent({ contract: "ChainlinkAggregator", event: "AnswerUpdated" }, async ({ event, context }) => {
  const aggregator = event.srcAddress.toLowerCase();
  const mapping = await context.ChainlinkAggregatorFeed.get(aggregator);
  const feedProxy = mapping?.feedProxy ?? SEED_AGGREGATOR_TO_PROXY[aggregator];
  // Every address ChainlinkAggregator ever watches comes from the seed list or from the
  // contractRegister handler above, both of which have a known feed -- this should be
  // unreachable, but fail loudly rather than write an orphaned PriceSnapshot if it isn't.
  if (feedProxy === undefined) {
    throw new Error(`ChainlinkAggregator ${aggregator} has no known feed`);
  }
  context.PriceSnapshot.set({
    id: `${event.transaction.hash}-${event.logIndex}`,
    feedProxy,
    answer: event.params.current,
    updatedAt: event.params.updatedAt,
    blockNumber: BigInt(event.block.number),
    blockTimestamp: BigInt(event.block.timestamp),
    transactionHash: event.transaction.hash,
    logIndex: event.logIndex,
  });
});
