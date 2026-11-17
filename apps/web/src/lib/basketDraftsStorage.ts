import { BASKET_COLORS, getBasketColor } from "./basketColors";
import type { BasketDraft } from "./mockBaskets";

/** Scoped to the one strategy a connected Safe can currently be building -- the wizard has no
 *  concept of multiple drafts or of editing an already-shipped strategy yet. Once a strategy
 *  ships, its group names live on the indexer (Strategy.groupNames, populated from
 *  BuildParametersAttested -- see the attest-strategy-group-names branch), not here; whatever
 *  future "ship" step lands should call clearDraftBaskets right after a successful ship so this
 *  draft can't resurface and get mistaken for a second strategy's names once multi-strategy UI
 *  exists. Keyed per-Safe so switching connected Safes in the same browser never shows one Safe's
 *  draft while building another's. */
function storageKey(safeAddress: string): string {
  return `aqua-pm-draft-baskets:${safeAddress.toLowerCase()}`;
}

/** Best-effort read -- undefined on anything from a private window to a hand-edited value that
 *  no longer matches BasketDraft's shape, so the caller always has a safe prop-based fallback.
 *
 *  A draft saved before a basket-palette change (e.g. the indigo/purple set this app used before
 *  the "Fix the Trim setup flow" rework) keeps whatever hex it was saved with forever -- nothing
 *  re-colors an already-persisted basket on its own. If any basket's stored color isn't one of
 *  the CURRENT palette's values, the whole draft predates it, so every basket is re-colored by
 *  its array index via getBasketColor -- same index a fresh `initialBaskets`/`addBasket()` would
 *  assign it. A basket created under the current palette always has a color in BASKET_COLORS, so
 *  this never fires for drafts that don't need it. */
export function loadDraftBaskets(safeAddress: string): BasketDraft[] | undefined {
  try {
    const raw = window.localStorage.getItem(storageKey(safeAddress));
    if (!raw) return undefined;
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return undefined;
    const isValid = parsed.every(
      (b) =>
        typeof b?.id === "string" &&
        typeof b?.name === "string" &&
        typeof b?.color === "string" &&
        Array.isArray(b?.tokenAddresses),
    );
    if (!isValid) return undefined;

    const baskets = parsed as BasketDraft[];
    const isStale = baskets.some((b) => !BASKET_COLORS.includes(b.color));
    return isStale ? baskets.map((b, i) => ({ ...b, color: getBasketColor(i).solid })) : baskets;
  } catch {
    return undefined;
  }
}

export function saveDraftBaskets(safeAddress: string, baskets: BasketDraft[]): void {
  try {
    window.localStorage.setItem(storageKey(safeAddress), JSON.stringify(baskets));
  } catch {
    // Private window, storage disabled, or quota exceeded -- names just won't survive a refresh.
  }
}

/** Call once this draft has shipped and become a real on-chain strategy -- its names now live on
 *  the indexer, and leaving the draft behind would let it resurface as stale state the next time
 *  this Safe starts building a strategy. Not called anywhere yet: no "ship" step exists in the
 *  wizard today (WizardFooter's onContinue past step 1 isn't wired to anything on-chain). */
export function clearDraftBaskets(safeAddress: string): void {
  try {
    window.localStorage.removeItem(storageKey(safeAddress));
  } catch {
    // Nothing to clean up if storage was never writable in the first place.
  }
}
