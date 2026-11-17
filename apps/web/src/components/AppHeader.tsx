import Link from "next/link";
import { AddressBadge } from "./AddressBadge";
import { NetworkBadge } from "./NetworkBadge";
import { TabNav, type TabNavItem } from "./TabNav";

export type AppHeaderProps = {
  /** Omit on pages with no tab navigation yet (e.g. the first-access introduction page). */
  tabs?: TabNavItem[];
  network: string;
  safeAddress: string;
  onSelectTab?: (label: string) => void;
};

/** Shared top nav bar: brand mark, an optional TabNav, and the network/Safe badge group. Reused
 *  on every Portfolio Manager page. Matches Figma's own NavigationHeader (node 546:25636,
 *  confirmed on the Baskets-Filled flow screen): transparent, sitting directly on the page's own
 *  background rather than a separate raised bar with its own border. The brand mark is the small
 *  vector logo mark (node 1124:... "brandoctopus_final 2"), not the landing page's larger
 *  pattern-filled mascot graphic (public/octopus.svg) -- a different asset, not a resize of the
 *  same one. Figma's own instance is rotated 180° and flipped on Y; net effect of composing
 *  those two transforms is a plain horizontal mirror, applied directly here as -scale-x-100.
 *  Wordmark: Unbounded Regular, 32px in Figma's own header -- scaled down to text-xl to fit this
 *  shorter, persistent app bar (py-3) rather than the landing page's taller hero header. */
export function AppHeader({ tabs, network, safeAddress, onSelectTab }: AppHeaderProps) {
  return (
    <header className="relative flex items-center justify-between px-16 py-3">
      <Link href="/dashboard" className="flex items-center gap-2">
        <img src="/trim-octopus-mark.svg" alt="" className="h-6 w-6 -scale-x-100" />
        <span className="font-display text-xl font-normal text-accent">Trim</span>
      </Link>

      {tabs && tabs.length > 0 && (
        <div className="absolute left-1/2 -translate-x-1/2">
          <TabNav tabs={tabs} onSelect={onSelectTab} />
        </div>
      )}

      <div className="flex items-center gap-2">
        <NetworkBadge network={network} />
        <AddressBadge label="Safe" address={safeAddress} />
      </div>
    </header>
  );
}
