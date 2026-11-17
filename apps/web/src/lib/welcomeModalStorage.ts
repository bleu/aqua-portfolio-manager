/** Keyed per-Safe so switching connected Safes in the same browser doesn't skip the welcome
 *  modal for a Safe that's never seen it, and doesn't re-show it for one that has. */
function storageKey(safeAddress: string): string {
  return `aqua-pm-seen-welcome:${safeAddress.toLowerCase()}`;
}

export function hasSeenWelcome(safeAddress: string): boolean {
  try {
    return window.localStorage.getItem(storageKey(safeAddress)) === "true";
  } catch {
    return false;
  }
}

export function markWelcomeSeen(safeAddress: string): void {
  try {
    window.localStorage.setItem(storageKey(safeAddress), "true");
  } catch {
    // Private window, storage disabled, or quota exceeded -- the modal just shows again next visit.
  }
}
