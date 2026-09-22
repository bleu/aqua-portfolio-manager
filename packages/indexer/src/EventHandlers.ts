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
