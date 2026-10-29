import { useState } from "react";
import { AppHeader } from "@/components/AppHeader";
import { Badge } from "@/components/Badge";
import { Button } from "@/components/Button";
import { EmptyState } from "@/components/EmptyState";
import type { TabNavItem } from "@/components/TabNav";
import { formatRelativeTime, truncateAddress } from "@/lib/format";
import { isReshipOf, programByteLength } from "@/lib/portfolioManagerEncoding";
import type { StrategyHistoryEntry } from "@/lib/useStrategyHistory";

/** Aqua gives a reshipped strategy a genuinely different strategyHash (see safeProposal.ts's own
 *  computeStrategyHash/buildReshipSteps doc comments for why that's correct, not a bug) -- so
 *  without this, two entries that are really the same logical strategy, reactivated, look like
 *  two unrelated ones in the list. Picks the immediate parent when a chain is more than one
 *  generation deep: the candidate with the longest real program (programByteLength, not
 *  encodedOrder.length -- see that function's own doc comment for why the raw string length
 *  can't tell two generations apart), since each further-back ancestor's program is a strict
 *  prefix of a closer one's. */
function findReshipParent(
  entry: StrategyHistoryEntry,
  entries: StrategyHistoryEntry[],
): StrategyHistoryEntry | undefined {
  let parent: StrategyHistoryEntry | undefined;
  for (const candidate of entries) {
    if (candidate.strategyHash === entry.strategyHash) continue;
    if (!isReshipOf(entry.encodedOrder, candidate.encodedOrder)) continue;
    if (!parent || programByteLength(candidate.encodedOrder) > programByteLength(parent.encodedOrder)) {
      parent = candidate;
    }
  }
  return parent;
}

export type PortfolioManagerHistoryPageProps = {
  network: string;
  safeAddress: string;
  entries: StrategyHistoryEntry[] | undefined;
  isLoading: boolean;
  error?: string;
  symbolForToken: (tokenAddress: string) => string;
  onSelectTab?: (label: string) => void;
  /** Reships an exact copy of a docked strategy (see safeProposal.ts's buildReshipSteps). Stays
   *  available even with an active strategy already on this Safe -- the caller docks that one
   *  first, batched with the reship, rather than this page hiding the option: a user who just
   *  deleted their strategy lands back on the "set up a new one" screen and may never think to
   *  check History again otherwise. */
  onReship?: (strategyHash: string) => void;
  /** strategyHash of the entry currently being reshipped, if any -- disables every Reship button
   *  while one is in flight, not just the one clicked. */
  reshippingStrategyHash?: string;
  reshipError?: string;
};

const TABS: TabNavItem[] = [
  { label: "Portfolio Manager" },
  { label: "History", active: true },
];

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
  const [confirmingStrategyHash, setConfirmingStrategyHash] =
    useState<string>();
  return (
    <div className="min-h-screen">
      <AppHeader
        tabs={TABS}
        network={network}
        safeAddress={safeAddress}
        onSelectTab={onSelectTab}
      />

      <div className="mx-auto max-w-4xl px-6 py-8">
        <h1 className="text-2xl font-bold text-white">Strategy history</h1>
        <p className="mt-1 text-sm text-gray-500">
          {truncateAddress(safeAddress)} · {network}
        </p>

        {error && <p className="mt-6 text-sm text-red-400">{error}</p>}

        {!error && isLoading && !entries && (
          <p className="mt-6 text-sm text-gray-500">Loading history…</p>
        )}

        {!error && entries && entries.length === 0 && (
          <EmptyState
            heading="No strategies yet"
            description="Strategies you ship or dock on this Safe will show up here."
            className="mt-6"
          />
        )}

        {entries && entries.length > 0 && (
          <div className="mt-6 space-y-4">
            {entries.map((entry) => {
              const reshipParent = findReshipParent(entry, entries);
              return (
                <div
                  key={entry.strategyHash}
                  className="rounded-xl border border-border bg-surface-card p-5"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex flex-wrap gap-1.5">
                      {entry.tokens.map((token) => (
                        <Badge key={token}>{symbolForToken(token)}</Badge>
                      ))}
                    </div>
                    {entry.isActive ? (
                      <Badge
                        className="border-transparent bg-positive/15 text-positive"
                        dotColor="#22c55e"
                      >
                        Active
                      </Badge>
                    ) : (
                      <Badge dotColor="#6b7280">Docked</Badge>
                    )}
                  </div>

                  <div className="mt-4 space-y-1.5 text-sm">
                    {reshipParent && (
                      <div className="text-gray-500">
                        <span>
                          ↳ Reactivated from{" "}
                          {truncateAddress(reshipParent.strategyHash)}
                        </span>
                      </div>
                    )}
                    <div className="flex items-center justify-between text-gray-400">
                      <span>
                        Shipped{" "}
                        {formatRelativeTime(Number(entry.shippedAt) * 1000)}
                      </span>
                      <span className="font-mono text-xs text-gray-500">
                        {truncateAddress(entry.shippedAtTxHash)}
                      </span>
                    </div>
                    {entry.dockedAt && entry.dockedAtTxHash && (
                      <div className="flex items-center justify-between text-gray-400">
                        <span>
                          Docked{" "}
                          {formatRelativeTime(Number(entry.dockedAt) * 1000)}
                        </span>
                        <span className="font-mono text-xs text-gray-500">
                          {truncateAddress(entry.dockedAtTxHash)}
                        </span>
                      </div>
                    )}
                  </div>

                  {!entry.isActive && onReship && (
                    <div className="mt-4">
                      {confirmingStrategyHash === entry.strategyHash ? (
                        <div className="rounded-lg border border-border bg-surface-raised p-4 text-sm">
                          <p className="text-gray-300">
                            This closes your current active strategy and
                            activates this one instead, in one transaction.
                          </p>
                          <div className="mt-3 flex items-center gap-3">
                            <Button
                              variant="secondary"
                              onClick={() => {
                                setConfirmingStrategyHash(undefined);
                                onReship(entry.strategyHash);
                              }}
                              disabled={!!reshippingStrategyHash}
                            >
                              Close current & reship this
                            </Button>
                            <Button
                              variant="secondary"
                              onClick={() =>
                                setConfirmingStrategyHash(undefined)
                              }
                              disabled={!!reshippingStrategyHash}
                            >
                              Cancel
                            </Button>
                          </div>
                        </div>
                      ) : (
                        <Button
                          variant="secondary"
                          onClick={() =>
                            hasActiveStrategy
                              ? setConfirmingStrategyHash(entry.strategyHash)
                              : onReship(entry.strategyHash)
                          }
                          disabled={!!reshippingStrategyHash}
                        >
                          {reshippingStrategyHash === entry.strategyHash
                            ? "Reshipping…"
                            : hasActiveStrategy
                              ? "Reship this strategy…"
                              : "Reship this strategy"}
                        </Button>
                      )}
                      {reshippingStrategyHash === entry.strategyHash &&
                        reshipError && (
                          <p className="mt-2 text-sm text-red-400">
                            {reshipError}
                          </p>
                        )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
