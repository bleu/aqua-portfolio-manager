import { indexer } from "envio";
import { onStrategyChanged } from "./compatibilityChecker";

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
    strategyBytes: event.params.strategy,
    isActive: true,
    shippedAtBlock: BigInt(event.block.number),
    shippedAtTimestamp: BigInt(event.block.timestamp),
    shippedAtTxHash: event.transaction.hash,
    dockedAtBlock: undefined,
    dockedAtTimestamp: undefined,
    dockedAtTxHash: undefined,
  });

  await onStrategyChanged(
    event.params.maker,
    event.chainId,
    BigInt(event.block.number),
    BigInt(event.block.timestamp),
    context,
  );
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
    dockedAtBlock: BigInt(event.block.number),
    dockedAtTimestamp: BigInt(event.block.timestamp),
    dockedAtTxHash: event.transaction.hash,
  });

  await onStrategyChanged(
    event.params.maker,
    event.chainId,
    BigInt(event.block.number),
    BigInt(event.block.timestamp),
    context,
  );
});
