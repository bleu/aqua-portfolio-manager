import type { SafeToken } from "./mockBaskets";

/** The wizard's one-time snapshot of the Safe's token balances/values, taken when the user
 *  enters step 1 (Baskets). Targets/Review/the activated page read this instead of calling
 *  `useSafeBalances` fresh, so a basket's "$X managed" figure can't drift between steps just
 *  because prices moved mid-wizard -- the reproduced bug this fixes (a basket showing $6,758 on
 *  Baskets and $6,747 on Review, from four independent live-fetch sites). Keyed per-Safe, same
 *  convention as basketDraftsStorage.ts. Does NOT replace `useSafeBalances`' `rawBalances` for
 *  building the actual ship transaction on Review -- that must stay live, never a stale snapshot. */
function storageKey(safeAddress: string): string {
  return `aqua-pm-balances-snapshot:${safeAddress.toLowerCase()}`;
}

export function loadBalancesSnapshot(safeAddress: string): SafeToken[] | undefined {
  try {
    const raw = window.localStorage.getItem(storageKey(safeAddress));
    if (!raw) return undefined;
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return undefined;
    const isValid = parsed.every(
      (t) =>
        typeof t?.symbol === "string" &&
        typeof t?.address === "string" &&
        typeof t?.balance === "number" &&
        typeof t?.value === "number",
    );
    return isValid ? (parsed as SafeToken[]) : undefined;
  } catch {
    return undefined;
  }
}

/** Only called from the Baskets step (step 1) -- re-entering step 1 is the one thing that's
 *  allowed to refresh the snapshot the rest of the wizard reads. */
export function saveBalancesSnapshot(safeAddress: string, tokens: SafeToken[]): void {
  try {
    window.localStorage.setItem(storageKey(safeAddress), JSON.stringify(tokens));
  } catch {
    // Private window, storage disabled, or quota exceeded -- later steps just fall back to live balances.
  }
}

export function clearBalancesSnapshot(safeAddress: string): void {
  try {
    window.localStorage.removeItem(storageKey(safeAddress));
  } catch {
    // Nothing to clean up if storage was never writable in the first place.
  }
}
