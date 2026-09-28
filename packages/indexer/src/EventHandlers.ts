import { indexer } from "envio";

function strategyId(maker: string, app: string, strategyHash: string): string {
  return `${maker}-${app}-${strategyHash}`.toLowerCase();
}

// Each proxy's `aggregator()` result as of 2026-09-28 (see config.yaml's ChainlinkAggregator
// seed comment) -- covers the AnswerUpdated handler below for the case where an aggregator's
// very first indexed event predates any ChainlinkAggregatorFeed row for it (nothing has ever
// pointed a AggregatorConfirmed at it yet, because it was already the live one at indexer setup).
const SEED_AGGREGATOR_TO_PROXY: Record<string, string> = {
  "0x05c84a58fe042275b37db038baacd15f410c7bb0": "0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70", // ETH/USD
  "0xe5ec87a39445b8d5b751b116802a53c5ae7e9df1": "0x64c911996d3c6ac71f9b455b1e8e7266bcbd848f", // BTC/USD
  "0x84640bb7b71b0963e8eb57ad379a0b204eb2fdc8": "0xf19d560eb8d2adf07bd6d13ed03e1d11215721f9", // USDT/USD
  "0x68be4c50235205ede361ac8244b1ee221cdda5e2": "0x7e860098f58bbfc8648a4311b374b1d669a2bc6b", // USDC/USD
};

indexer.onEvent({ contract: "Aqua", event: "Shipped" }, async ({ event, context }) => {
  const id = strategyId(event.params.maker, event.params.app, event.params.strategyHash);
  context.Strategy.set({
    id,
    maker: event.params.maker,
    app: event.params.app,
    strategyHash: event.params.strategyHash,
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
