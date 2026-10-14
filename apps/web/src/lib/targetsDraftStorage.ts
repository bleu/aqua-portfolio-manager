/** Mirrors basketDraftsStorage.ts's lifecycle and per-Safe scoping, for the Targets step's
 *  per-basket percentages -- see that file's own doc comment for the full rationale. */
function storageKey(safeAddress: string): string {
  return `aqua-pm-draft-targets:${safeAddress.toLowerCase()}`;
}

export function loadDraftTargets(safeAddress: string): Record<string, number> | undefined {
  try {
    const raw = window.localStorage.getItem(storageKey(safeAddress));
    if (!raw) return undefined;
    const parsed = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null) return undefined;
    const isValid = Object.values(parsed).every((v) => typeof v === "number");
    return isValid ? (parsed as Record<string, number>) : undefined;
  } catch {
    return undefined;
  }
}

export function saveDraftTargets(safeAddress: string, targetsPct: Record<string, number>): void {
  try {
    window.localStorage.setItem(storageKey(safeAddress), JSON.stringify(targetsPct));
  } catch {
    // Private window, storage disabled, or quota exceeded.
  }
}

export function clearDraftTargets(safeAddress: string): void {
  try {
    window.localStorage.removeItem(storageKey(safeAddress));
  } catch {
    // Nothing to clean up if storage was never writable.
  }
}
