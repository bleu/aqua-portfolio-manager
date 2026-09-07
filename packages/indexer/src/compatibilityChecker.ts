import type { EvmOnEventContext } from "envio";
import { isPmApp } from "./pmAppRegistry";

type Context = EvmOnEventContext;

/**
 * Detection rule: conservative and structural, not case-by-case. We can't generally inspect an
 * arbitrary third-party app's strategy bytes and prove whether its trades cross PM's declared
 * token-universe boundary -- apps are opaque swap-vm programs. So: flag any maker that has an
 * active PM-app strategy AND an active non-PM-app strategy at the same time, full stop. False
 * positives are an acceptable cost for a warning surface, not an enforcement mechanism --
 * BasketScopeGuard remains the actual enforcement layer for wallets it's installed on.
 *
 * Runs on every Shipped/Docked for the affected maker (not a periodic sweep) -- cheap, since it
 * only ever looks at one maker's own active strategies, and stays correct immediately rather
 * than up to a poll interval stale.
 */
export async function onStrategyChanged(
  maker: string,
  chainId: number,
  blockNumber: bigint,
  blockTimestamp: bigint,
  context: Context,
): Promise<void> {
  const active = await context.Strategy.getWhere({ maker: { _eq: maker }, isActive: { _eq: true } });
  const pmStrategies = active.filter((s) => isPmApp(s.app, chainId));
  const otherStrategies = active.filter((s) => !isPmApp(s.app, chainId));

  for (const pm of pmStrategies) {
    for (const other of otherStrategies) {
      const id = `${pm.id}-${other.id}`;
      const existing = await context.CompatibilityAlert.get(id);
      if (existing === undefined) {
        context.CompatibilityAlert.set({
          id,
          maker,
          pmStrategyId: pm.id,
          conflictingStrategyId: other.id,
          conflictingApp: other.app,
          status: "OPEN",
          detectedAtBlock: blockNumber,
          detectedAtTimestamp: blockTimestamp,
          resolvedAtBlock: undefined,
          resolvedAtTimestamp: undefined,
        });
      }
    }
  }

  // Resolve alerts whose pair is no longer both-active (either strategy docked). Resolved, not
  // deleted -- a maker's past conflicts stay queryable for audit/support purposes.
  const openAlerts = await context.CompatibilityAlert.getWhere({
    maker: { _eq: maker },
    status: { _eq: "OPEN" },
  });
  const activeIds = new Set(active.map((s) => s.id));
  for (const alert of openAlerts) {
    if (!activeIds.has(alert.pmStrategyId) || !activeIds.has(alert.conflictingStrategyId)) {
      context.CompatibilityAlert.set({
        ...alert,
        status: "RESOLVED",
        resolvedAtBlock: blockNumber,
        resolvedAtTimestamp: blockTimestamp,
      });
    }
  }
}
