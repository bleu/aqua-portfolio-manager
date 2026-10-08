import { AddressBadge } from "./AddressBadge";
import { NetworkBadge } from "./NetworkBadge";
import { TabNav, type TabNavItem } from "./TabNav";

export type AppHeaderProps = {
  tabs: TabNavItem[];
  network: string;
  safeAddress: string;
  onSelectTab?: (label: string) => void;
};

/** Shared top nav bar: brand mark, TabNav, and the network/Safe badge group. Reused on every Portfolio Manager page. */
export function AppHeader({ tabs, network, safeAddress, onSelectTab }: AppHeaderProps) {
  return (
    <header className="flex items-center justify-between border-b border-border bg-surface-raised px-6 py-3">
      <div className="flex items-center gap-8">
        <div className="flex items-center gap-2">
          <span className="flex h-6 w-6 items-center justify-center rounded-md bg-white text-xs font-bold text-surface">
            P
          </span>
          <span className="text-sm font-medium text-gray-100">Portfolio Manager</span>
        </div>
        <TabNav tabs={tabs} onSelect={onSelectTab} />
      </div>

      <div className="flex items-center gap-2">
        <NetworkBadge network={network} />
        <AddressBadge label="Safe" address={safeAddress} />
      </div>
    </header>
  );
}
