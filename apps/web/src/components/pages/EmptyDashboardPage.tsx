import { AppHeader } from "@/components/AppHeader";
import { Button } from "@/components/Button";
import { EmptyState } from "@/components/EmptyState";
import type { TabNavItem } from "@/components/TabNav";

/** Sized to match Figma's 33x33 icon in a 1438-wide frame (33/1438 ≈ 2.29vw). */
function TargetIcon() {
  return (
    <svg className="h-[2.29vw] w-[2.29vw]" viewBox="0 0 100 100" fill="currentColor" aria-hidden="true">
      <path d="M88.47,50C88.19,66.07,78.32,80.78,63,86.23a38.48,38.48,0,0,1-46-56A38.85,38.85,0,0,1,57.82,12.32C75.7,16,88.16,32,88.47,50c0,1.93,3,1.93,3,0A42,42,0,0,0,64.41,11.11a41.48,41.48,0,0,0-50,60.19A41.89,41.89,0,0,0,57.29,90.83c19.79-3.48,33.84-21,34.19-40.83C91.5,48.07,88.5,48.07,88.47,50Z" />
      <path d="M77.63,50C77.28,65.05,65.32,77.63,50,77.63A27.89,27.89,0,0,1,22.37,50,27.88,27.88,0,0,1,50,22.37c15.33,0,27.28,12.55,27.63,27.63,0,1.93,3,1.93,3,0A31.09,31.09,0,0,0,60.83,21.35a30.88,30.88,0,0,0-34.62,9.37C8.63,52.48,28.32,85.28,55.78,80.08,70.27,77.33,80.29,64.5,80.63,50,80.67,48.07,77.67,48.07,77.63,50Z" />
    </svg>
  );
}

export type EmptyDashboardPageProps = {
  network: string;
  safeAddress: string;
  onStartSetup?: () => void;
  onSelectTab?: (label: string) => void;
};

const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];

/** BLEUDEV-410 — "03 · Empty dashboard": shown to a returning LP whose Safe has no active strategy. */
export function EmptyDashboardPage({ network, safeAddress, onStartSetup, onSelectTab }: EmptyDashboardPageProps) {
  return (
    <div className="flex min-h-screen flex-col">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} onSelectTab={onSelectTab} />

      <div className="flex w-full flex-1 flex-col px-6 py-10">
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
