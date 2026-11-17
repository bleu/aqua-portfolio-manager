function storageKey(safeAddress: string): string {
  return `aqua-pm-dismissed-safe-banner:${safeAddress.toLowerCase()}`;
}

export function hasDismissedSafeBanner(safeAddress: string): boolean {
  try {
    return window.localStorage.getItem(storageKey(safeAddress)) === "true";
  } catch {
    return false;
  }
}

export function dismissSafeBanner(safeAddress: string): void {
  try {
    window.localStorage.setItem(storageKey(safeAddress), "true");
  } catch {
    // Private window, storage disabled, or quota exceeded -- the banner just shows again next visit.
  }
}
