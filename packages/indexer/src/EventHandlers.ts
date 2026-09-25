import { indexer } from "envio";

function strategyId(maker: string, app: string, strategyHash: string): string {
  return `${maker}-${app}-${strategyHash}`.toLowerCase();
}

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
