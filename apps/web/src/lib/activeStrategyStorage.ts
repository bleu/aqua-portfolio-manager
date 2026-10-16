import type { BasketDraft } from "./mockBaskets";
import type { DraftParameters } from "./parametersDraftStorage";

/** A frozen snapshot of the strategy that was actually shipped, taken right before the wizard's
 *  in-progress drafts (basketDraftsStorage.ts etc.) are cleared -- see PortfolioManagerActivatedPage's
 *  route. The real source of truth is on-chain/the indexer; this is only a placeholder so the
 *  dashboard has something real-shaped to render until that's wired up. Keyed per-Safe like every
 *  other draft in this app. */
export type ActiveStrategySnapshot = {
  baskets: BasketDraft[];
  targetsPct: Record<string, number>;
  parameters: DraftParameters;
  activatedAt: number;
};

function storageKey(safeAddress: string): string {
  return `aqua-pm-active-strategy:${safeAddress.toLowerCase()}`;
}

export function saveActiveStrategy(safeAddress: string, snapshot: ActiveStrategySnapshot): void {
  try {
    window.localStorage.setItem(storageKey(safeAddress), JSON.stringify(snapshot));
  } catch {
    // Private window, storage disabled, or quota exceeded.
  }
}

export function loadActiveStrategy(safeAddress: string): ActiveStrategySnapshot | undefined {
  try {
    const raw = window.localStorage.getItem(storageKey(safeAddress));
    if (!raw) return undefined;
    const parsed = JSON.parse(raw);
    const isValid =
      Array.isArray(parsed?.baskets) &&
      typeof parsed?.targetsPct === "object" &&
      typeof parsed?.parameters === "object";
    return isValid ? (parsed as ActiveStrategySnapshot) : undefined;
  } catch {
    return undefined;
  }
}
