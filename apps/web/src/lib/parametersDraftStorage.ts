/** Mirrors basketDraftsStorage.ts's lifecycle and per-Safe scoping, for the Parameters step's
 *  price-deviation and LP-fee selections -- see that file's own doc comment for the full rationale. */
export type DraftParameters = { priceDeviationPct: number; lpFeePct: number };

function storageKey(safeAddress: string): string {
  return `aqua-pm-draft-parameters:${safeAddress.toLowerCase()}`;
}

export function loadDraftParameters(safeAddress: string): DraftParameters | undefined {
  try {
    const raw = window.localStorage.getItem(storageKey(safeAddress));
    if (!raw) return undefined;
    const parsed = JSON.parse(raw);
    const isValid = typeof parsed?.priceDeviationPct === "number" && typeof parsed?.lpFeePct === "number";
    return isValid ? (parsed as DraftParameters) : undefined;
  } catch {
    return undefined;
  }
}

export function saveDraftParameters(safeAddress: string, params: DraftParameters): void {
  try {
    window.localStorage.setItem(storageKey(safeAddress), JSON.stringify(params));
  } catch {
    // Private window, storage disabled, or quota exceeded.
  }
}

export function clearDraftParameters(safeAddress: string): void {
  try {
    window.localStorage.removeItem(storageKey(safeAddress));
  } catch {
    // Nothing to clean up if storage was never writable.
  }
}
