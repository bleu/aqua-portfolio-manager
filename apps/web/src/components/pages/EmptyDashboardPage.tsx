import { AppHeader } from "@/components/AppHeader";
import { Button } from "@/components/Button";
import { EmptyState } from "@/components/EmptyState";
import type { TabNavItem } from "@/components/TabNav";

function TargetIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
      <circle cx="10" cy="10" r="7" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="10" cy="10" r="2.5" fill="currentColor" />
    </svg>
  );
}

export type EmptyDashboardPageProps = {
  network: string;
  safeAddress: string;
  onStartSetup?: () => void;
};

const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];

/** BLEUDEV-410 — "03 · Empty dashboard": shown to a returning LP whose Safe has no active strategy. */
export function EmptyDashboardPage({ network, safeAddress, onStartSetup }: EmptyDashboardPageProps) {
  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-5xl px-6 py-10">
        <h1 className="text-2xl font-semibold text-white">Portfolio Manager</h1>
        <p className="mt-1 text-sm text-gray-400">Monitor group targets, routed trades, and LP fees earned.</p>

        <div className="mt-6">
          <EmptyState
            icon={<TargetIcon />}
            heading="Set up your Portfolio Manager"
            description="Choose tokens, set group targets, and define price protection. Once active, routed trades help maintain the allocation while your portfolio earns LP fees."
            action={<Button onClick={onStartSetup}>Start setup</Button>}
          />
        </div>
      </div>
    </div>
  );
}
