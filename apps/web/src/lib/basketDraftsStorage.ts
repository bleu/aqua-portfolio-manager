import type { BasketDraft } from "./mockBaskets";

/** Keyed per-Safe so switching connected Safes in the same browser never shows one Safe's
 *  in-progress baskets while building another's. */
function storageKey(safeAddress: string): string {
  return `aqua-pm-baskets:${safeAddress.toLowerCase()}`;
}

/** Best-effort read -- undefined on anything from a private window to a hand-edited value that
 *  no longer matches BasketDraft's shape, so the caller always has a safe prop-based fallback. */
export function loadBasketDrafts(safeAddress: string): BasketDraft[] | undefined {
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
    return isValid ? (parsed as BasketDraft[]) : undefined;
  } catch {
    return undefined;
  }
}

export function saveBasketDrafts(safeAddress: string, baskets: BasketDraft[]): void {
  try {
    window.localStorage.setItem(storageKey(safeAddress), JSON.stringify(baskets));
  } catch {
    // Private window, storage disabled, or quota exceeded -- names just won't survive a refresh.
  }
}
