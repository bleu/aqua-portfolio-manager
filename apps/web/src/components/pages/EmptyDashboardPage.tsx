import { AppHeader } from "@/components/AppHeader";
import { Button } from "@/components/Button";
import { EmptyState } from "@/components/EmptyState";
import type { TabNavItem } from "@/components/TabNav";

/** Sized to match Figma's 33x33 icon in a 1438-wide frame (33/1438 ≈ 2.29vw). */
function TargetIcon() {
  return (
    <svg className="h-[2.29vw] w-[2.29vw]" viewBox="0 0 20 20" fill="none" aria-hidden="true">
      <circle cx="10" cy="10" r="7" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="10" cy="10" r="2.5" stroke="currentColor" strokeWidth="1.5" />
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
    <div className="flex min-h-screen flex-col">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="flex w-full flex-1 flex-col px-[5.81vw] py-10">
        <h1 className="text-2xl font-semibold text-white">Portfolio Manager</h1>
        <p className="mt-1 text-sm text-gray-400">Monitor group targets, routed trades, and LP fees earned.</p>

        <div className="mt-6 flex flex-1 flex-col">
          <EmptyState
            icon={<TargetIcon />}
            heading="Set up your Portfolio Manager"
            description="Choose tokens, set group targets, and define price protection. Once active, routed trades help maintain the allocation while your portfolio earns LP fees."
            action={
              <Button size="lg" onClick={onStartSetup}>
                Start setup
              </Button>
            }
            className="flex-1"
          />
        </div>
      </div>
    </div>
  );
}
