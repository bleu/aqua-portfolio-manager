import { AppHeader } from "@/components/AppHeader";
import { Badge } from "@/components/Badge";
import { Button } from "@/components/Button";
import { EmptyState } from "@/components/EmptyState";
import type { TabNavItem } from "@/components/TabNav";
import { formatRelativeTime, truncateAddress } from "@/lib/format";
import type { StrategyHistoryEntry } from "@/lib/useStrategyHistory";

export type PortfolioManagerHistoryPageProps = {
  network: string;
  safeAddress: string;
  entries: StrategyHistoryEntry[] | undefined;
  isLoading: boolean;
  error?: string;
  symbolForToken: (tokenAddress: string) => string;
  onSelectTab?: (label: string) => void;
  /** Reships an exact copy of a docked strategy (see safeProposal.ts's buildReshipSteps) --
   *  omitted entirely (no button renders) when there's already an active strategy on this Safe,
   *  since Aqua has no built-in "one active strategy per Safe" limit and this app's dashboard
   *  isn't built to show two. */
  onReship?: (strategyHash: string) => void;
  /** strategyHash of the entry currently being reshipped, if any -- disables every Reship button
   *  while one is in flight, not just the one clicked. */
  reshippingStrategyHash?: string;
  reshipError?: string;
};

const TABS: TabNavItem[] = [{ label: "Portfolio Manager" }, { label: "History", active: true }];

/** BLEUDEV-419's History tab -- every strategy this Safe has ever shipped or docked, newest
 *  first, read straight from the indexer (the same source of truth the dashboard itself now
 *  uses). */
export function PortfolioManagerHistoryPage({
  network,
  safeAddress,
  entries,
  isLoading,
  error,
  symbolForToken,
  onSelectTab,
  onReship,
  reshippingStrategyHash,
  reshipError,
}: PortfolioManagerHistoryPageProps) {
  const hasActiveStrategy = !!entries?.some((e) => e.isActive);
  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} onSelectTab={onSelectTab} />

      <div className="mx-auto max-w-4xl px-6 py-8">
        <h1 className="text-2xl font-bold text-white">Strategy history</h1>
        <p className="mt-1 text-sm text-gray-500">
          {truncateAddress(safeAddress)} · {network}
        </p>

        {error && <p className="mt-6 text-sm text-red-400">{error}</p>}

        {!error && isLoading && !entries && <p className="mt-6 text-sm text-gray-500">Loading history…</p>}

        {!error && entries && entries.length === 0 && (
          <EmptyState
            heading="No strategies yet"
            description="Strategies you ship or dock on this Safe will show up here."
            className="mt-6"
          />
        )}

        {entries && entries.length > 0 && (
          <div className="mt-6 space-y-4">
            {entries.map((entry) => (
              <div key={entry.strategyHash} className="rounded-xl border border-border bg-surface-card p-5">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex flex-wrap gap-1.5">
                    {entry.tokens.map((token) => (
                      <Badge key={token}>{symbolForToken(token)}</Badge>
                    ))}
                  </div>
                  {entry.isActive ? (
                    <Badge className="border-transparent bg-positive/15 text-positive" dotColor="#22c55e">
                      Active
                    </Badge>
                  ) : (
                    <Badge dotColor="#6b7280">Docked</Badge>
                  )}
                </div>

                <div className="mt-4 space-y-1.5 text-sm">
                  <div className="flex items-center justify-between text-gray-400">
                    <span>Shipped {formatRelativeTime(Number(entry.shippedAt) * 1000)}</span>
                    <span className="font-mono text-xs text-gray-500">{truncateAddress(entry.shippedAtTxHash)}</span>
                  </div>
                  {entry.dockedAt && entry.dockedAtTxHash && (
                    <div className="flex items-center justify-between text-gray-400">
                      <span>Docked {formatRelativeTime(Number(entry.dockedAt) * 1000)}</span>
                      <span className="font-mono text-xs text-gray-500">{truncateAddress(entry.dockedAtTxHash)}</span>
                    </div>
                  )}
                </div>

                {!entry.isActive && !hasActiveStrategy && onReship && (
                  <div className="mt-4">
                    <Button
                      variant="secondary"
                      onClick={() => onReship(entry.strategyHash)}
                      disabled={!!reshippingStrategyHash}
                    >
                      {reshippingStrategyHash === entry.strategyHash ? "Reshipping…" : "Reship this strategy"}
                    </Button>
                    {reshippingStrategyHash === entry.strategyHash && reshipError && (
                      <p className="mt-2 text-sm text-red-400">{reshipError}</p>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
