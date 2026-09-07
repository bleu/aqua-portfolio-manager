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
});

indexer.onEvent({ contract: "Aqua", event: "Pushed" }, async ({ event, context }) => {
  const id = strategyId(event.params.maker, event.params.app, event.params.strategyHash);
  const strategy = await context.Strategy.get(id);
  // A Pushed event for a strategy we have no Shipped record for is expected once start_block
  // is set later than that strategy's ship() -- ignore rather than fail, this handler only
  // enriches an existing row, it never creates one.
  if (strategy === undefined) return;
  // Pushed also fires on every later trade's pull/push cycle -- only the batch emitted in the
  // exact same transaction as this strategy's own Shipped event is its declared token universe.
  if (strategy.shippedAtTxHash !== event.transaction.hash) return;
  if (strategy.tokens.includes(event.params.token)) return;
  context.Strategy.set({ ...strategy, tokens: [...strategy.tokens, event.params.token] });
});

indexer.onEvent({ contract: "Aqua", event: "Docked" }, async ({ event, context }) => {
  const id = strategyId(event.params.maker, event.params.app, event.params.strategyHash);
  // A Docked event for a strategy this indexer never saw Shipped for means either a missed
  // backfill range or a start_block set after that strategy's ship -- a loud failure is better
  // than a silently-wrong "active" strategy that was actually docked.
  const strategy = await context.Strategy.getOrThrow(id);
  context.Strategy.set({
    ...strategy,
    isActive: false,
    dockedAt: BigInt(event.block.timestamp),
    dockedAtTxHash: event.transaction.hash,
  });
});
