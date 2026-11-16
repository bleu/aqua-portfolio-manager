"use client";

import { useRef, useState } from "react";
import { AllocationHistoryChart, type AllocationHistorySeries } from "@/components/AllocationHistoryChart";
import { AppHeader } from "@/components/AppHeader";
import { Button } from "@/components/Button";
import { IconButton } from "@/components/IconButton";
import { TokenListRow } from "@/components/TokenListRow";
import { VolumeBarChart, type VolumeBar } from "@/components/VolumeBarChart";
import { MoreIcon } from "@/components/icons";
import { buildNavTabs } from "@/lib/navTabs";
import { formatRelativeTime, formatUsd } from "@/lib/format";

const TABS = buildNavTabs("portfolio-manager");
const TIME_RANGES = ["30d", "90d", "180d"] as const;
type TimeRange = (typeof TIME_RANGES)[number];
const CHART_TABS = ["Allocation", "Volume"] as const;
type ChartTab = (typeof CHART_TABS)[number];

export type DashboardToken = {
  symbol: string;
  name: string;
  address: string;
  iconUrl?: string;
  balance: number;
  value: number;
};

export type DashboardBasket = {
  id: string;
  name: string;
  color: string;
  managedValue: number;
  currentPct: number;
  targetPct: number;
  tokens: DashboardToken[];
};

export type DashboardTargetRecap = { id: string; name: string; tokenSymbols: string[]; targetPct: number };

export type ActivePortfolioManagerDashboardPageProps = {
  network: string;
  safeAddress: string;
  updatedAt: number;
  managedValue: number;
  netLpFeesEarned: number;
  routedVolume: number;
  routedTransactionCount: number;
  baskets: DashboardBasket[];
  chartSeries: AllocationHistorySeries[];
  /** Daily routed-volume buckets for the Volume tab's bar chart -- omitted (or empty) renders the
   *  Claude Artifact's Dashboard_Empty.dc.html "No activity yet" state, which is honestly this
   *  app's only real state today: nothing here reads historical routed-volume data yet. */
  volumeSeries?: VolumeBar[];
  priceDeviationPct: number;
  lpFeePct: number;
  targetsRecap: DashboardTargetRecap[];
  onDeleteStrategy?: () => void;
  isDeletingStrategy?: boolean;
  deleteStrategyError?: string;
  onUpdateStrategy?: () => void;
  /** False while the indexer lookup for this Safe's active strategy hash/tokens (needed to build
   *  the dock() call) is still in flight -- without it, "Delete" would silently no-op. */
  canDeleteStrategy?: boolean;
  onSelectTab?: (label: string) => void;
  /** "paused" matches the Claude Artifact's Dashboard_Paused.dc.html -- the strategy itself is
   *  still active on-chain, but automatic rebalancing has stopped because one basket's price
   *  deviation exceeded the configured limit. Defaults to "active" (today's only real state; no
   *  on-chain "paused" signal is read yet, so a caller must pass both this and `pausedAlert`
   *  explicitly once one exists). */
  status?: "active" | "paused";
  pausedAlert?: {
    affectedBasketName: string;
    priceDeviationPct: number;
    yourLimitPct: number;
  };
};

/** Target-allocation ring (Dashboard_Allocation.dc.html's 48px basket-card icon): the arc length
 *  is the basket's TARGET share, not its current one -- confirmed directly against the artifact's
 *  own stroke-dasharray values (e.g. 35% target -> "41.8 119.4", where 119.4 is the full
 *  circumference of r=19). */
function TargetRing({ targetPct, color }: { targetPct: number; color: string }) {
  const r = 19;
  const circumference = 2 * Math.PI * r;
  const filled = (targetPct / 100) * circumference;
  return (
    <svg width="48" height="48" viewBox="0 0 48 48" aria-hidden="true">
      <circle cx="24" cy="24" r={r} fill="none" stroke="#2a2e33" strokeWidth="5" />
      <circle
        cx="24"
        cy="24"
        r={r}
        fill="none"
        stroke={color}
        strokeWidth="5"
        strokeLinecap="round"
        strokeDasharray={`${filled} ${circumference}`}
        transform="rotate(-100 24 24)"
      />
    </svg>
  );
}

/** BLEUDEV-419 — the real-data counterpart to the "No active Portfolio Manager" screen, shown at
 *  the same /dashboard route once the connected Safe has an active strategy. Rebuilt (Round 2,
 *  Trim design-alignment phase 7) to match the Claude Artifact's Dashboard_Allocation/Volume/Empty
 *  /Paused.dc.html exactly -- the Overview card, the Allocation/Volume tab switcher with 30/90/180d
 *  ranges, ring-icon basket cards, and a Settings recap section, none of which existed before. The
 *  design's "Fees" tab is intentionally left out: its content was never specified and the user
 *  explicitly said not to invent it. */
export function ActivePortfolioManagerDashboardPage({
  network,
  safeAddress,
  updatedAt,
  managedValue,
  netLpFeesEarned,
  routedVolume,
  routedTransactionCount,
  baskets,
  chartSeries,
  volumeSeries,
  priceDeviationPct,
  lpFeePct,
  targetsRecap,
  onDeleteStrategy,
  isDeletingStrategy,
  deleteStrategyError,
  canDeleteStrategy = true,
  onSelectTab,
  onUpdateStrategy,
  status = "active",
  pausedAlert,
}: ActivePortfolioManagerDashboardPageProps) {
  const [range, setRange] = useState<TimeRange>("30d");
  const [chartTab, setChartTab] = useState<ChartTab>("Allocation");
  const [showMoreMenu, setShowMoreMenu] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const basketsRef = useRef<HTMLDivElement>(null);

  const hasActivity = chartTab === "Allocation" ? chartSeries.some((s) => s.points.length > 0) : (volumeSeries?.length ?? 0) > 0;

  function scrollBaskets(direction: -1 | 1) {
    basketsRef.current?.scrollBy({ left: direction * 340, behavior: "smooth" });
  }

  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} onSelectTab={onSelectTab} />

      <div className="mx-auto max-w-[1636px] px-[62px] py-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-3.5">
              <h1 className="text-[26px] font-semibold text-white">Portfolio Manager</h1>
              {status === "paused" ? (
                <span className="flex h-7 items-center gap-1.5 rounded-full bg-[#d7c39c] px-3 text-xs font-medium text-[#0b0d10]">
                  <i className="size-1.5 rounded-full bg-[#0b0d10]/70" />
                  Paused
                </span>
              ) : (
                <span className="flex h-7 items-center gap-1.5 rounded-full bg-accent px-3 text-xs font-medium text-[#0b0d10]">
                  <i className="size-1.5 rounded-full bg-[#0b0d10]/70" />
                  Active
                </span>
              )}
            </div>
            <p className="mt-1.5 text-xs text-gray-500">Updated {formatRelativeTime(updatedAt)}</p>
          </div>
          <div className="relative flex items-center gap-2">
            <IconButton aria-label="More options" onClick={() => setShowMoreMenu((v) => !v)}>
              <MoreIcon className="size-4" />
            </IconButton>
            {showMoreMenu && (
              <div className="absolute top-12 right-0 z-10 w-52 rounded-[10px] border border-border bg-surface-raised py-1 shadow-lg">
                <button
                  type="button"
                  className="w-full px-3 py-2 text-left text-sm text-red-400 hover:bg-red-400/10"
                  onClick={() => {
                    setShowMoreMenu(false);
                    setShowDeleteConfirm(true);
                  }}
                >
                  Delete Portfolio Manager
                </button>
              </div>
            )}
          </div>
        </div>

        {status === "paused" && pausedAlert && (
          <div className="mt-4 flex flex-wrap gap-7 rounded-[34px] border border-[#b79f6e] bg-[#0f1114] p-6">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#c9ad78" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="mt-0.5 shrink-0">
              <path d="M12 4l9 16H3L12 4zM12 10v4M12 17v.5" />
            </svg>
            <div className="flex-1">
              <p className="text-[17px] font-semibold text-white">Rebalancing was paused to protect your portfolio</p>
              <p className="mt-2.5 max-w-[640px] text-[13px] leading-[1.5] text-[#8b9096]">
                The {pausedAlert.affectedBasketName} basket is trading outside its allowed deviation from the oracle
                price. Trim has paused automatic rebalancing to avoid unfavorable trades and potential losses.
              </p>
              <div className="mt-5 flex flex-wrap gap-7">
                <div>
                  <p className="text-xs text-[#8b9096]">Affected basket</p>
                  <p className="mt-1.5 text-[17px] font-medium text-white">{pausedAlert.affectedBasketName}</p>
                </div>
                <div className="border-l border-[#262a2f] pl-7">
                  <p className="text-xs text-[#8b9096]">Price deviation</p>
                  <p className="mt-1.5 text-[17px] font-medium text-white">{pausedAlert.priceDeviationPct}%</p>
                </div>
                <div className="border-l border-[#262a2f] pl-7">
                  <p className="text-xs text-[#8b9096]">Your price limit</p>
                  <p className="mt-1.5 text-[17px] font-medium text-white">{pausedAlert.yourLimitPct}%</p>
                </div>
              </div>
            </div>
            <div className="flex-1 border-l border-[#262a2f] pl-7">
              <p className="text-[17px] font-semibold text-white">What to do</p>
              <p className="mt-2.5 text-[13px] leading-[1.5] text-[#8b9096]">
                Make a manual trade in your wallet to bring your baskets to their target allocation. Trim will
                automatically resume once your target allocation is restored.
              </p>
            </div>
          </div>
        )}

        {showDeleteConfirm && (
          <div className="mt-4 rounded-lg border border-red-400/40 bg-red-400/10 p-4 text-sm text-red-300">
            <p className="font-medium">Delete this Portfolio Manager?</p>
            <p className="mt-1 text-red-300/90">
              This deactivates the Portfolio Manager and stops it from managing your baskets. Your tokens stay in
              your Safe exactly where they are -- deleting doesn&apos;t move or withdraw anything.
            </p>
            {deleteStrategyError && <p className="mt-2 text-red-300">{deleteStrategyError}</p>}
            <div className="mt-3 flex items-center gap-3">
              <Button
                variant="secondary"
                className="border-red-400/40 text-red-300 hover:bg-red-400/10"
                onClick={onDeleteStrategy}
                disabled={isDeletingStrategy || !canDeleteStrategy}
              >
                {isDeletingStrategy ? "Deleting…" : canDeleteStrategy ? "Delete Portfolio Manager" : "Loading…"}
              </Button>
              <Button variant="secondary" onClick={() => setShowDeleteConfirm(false)} disabled={isDeletingStrategy}>
                Cancel
              </Button>
            </div>
          </div>
        )}

        <div className="mt-8 flex flex-wrap gap-8">
          <div className="flex min-h-[400px] flex-[0_0_348px] flex-col justify-between rounded-[30px] border border-white/[0.03] bg-[#16181b] p-6">
            <div className="flex items-center justify-between text-[17px] text-white">
              Overview
              <span className="flex h-[30px] items-center rounded-lg border border-[#5c6b73] bg-[#27333a] px-2.5 text-xs text-white">
                {range}
              </span>
            </div>
            <div>
              <p className="text-[15px] text-white">Total managed value</p>
              <p className="mt-2.5 text-[34px] font-semibold text-white">{formatUsd(managedValue)}</p>
            </div>
            <div className="flex items-center border-t border-[#262a2f] pt-6">
              <div className="flex-1">
                <p className="text-[15px] text-white">Net LP fees earned</p>
                <p className="mt-1.5 text-[11px] text-[#8b9096]">After protocol fee</p>
              </div>
              <p className="text-xl font-medium text-accent">{formatUsd(netLpFeesEarned)}</p>
            </div>
            <div className="flex items-center border-t border-[#262a2f] pt-6">
              <div className="flex-1">
                <p className="text-[15px] text-white">Routed volume</p>
                <p className="mt-1.5 text-[11px] text-[#8b9096]">{routedTransactionCount} transactions</p>
              </div>
              <p className="text-[19px] font-semibold text-white">{formatUsd(routedVolume)}</p>
            </div>
          </div>

          <div className="min-h-[400px] min-w-0 flex-[1_1_640px] rounded-[30px] border border-white/[0.03] bg-[#16181b] p-6">
            <div className="flex flex-wrap items-center justify-between gap-4">
              <div className="flex w-full max-w-[512px] gap-1 rounded-full bg-[#1c2024] p-1">
                {CHART_TABS.map((tab) => (
                  <button
                    key={tab}
                    type="button"
                    onClick={() => setChartTab(tab)}
                    className={
                      tab === chartTab
                        ? "h-[52px] flex-1 rounded-full bg-gradient-to-b from-[#e3f3f5] to-[#8fc7cf] text-[15px] font-semibold text-[#0b0d10]"
                        : "h-[52px] flex-1 rounded-full text-[15px] font-medium text-[#c3c8cc]"
                    }
                  >
                    {tab}
                  </button>
                ))}
              </div>
              <div className="flex gap-1 rounded-full bg-[#1c2024] p-1">
                {TIME_RANGES.map((option) => (
                  <button
                    key={option}
                    type="button"
                    onClick={() => setRange(option)}
                    className={
                      option === range
                        ? "h-[52px] rounded-full bg-gradient-to-b from-[#e3f3f5] to-[#8fc7cf] px-7 text-[15px] font-semibold text-[#0b0d10]"
                        : "h-[52px] rounded-full px-7 text-[15px] font-medium text-[#c3c8cc]"
                    }
                  >
                    {option}
                  </button>
                ))}
              </div>
            </div>

            {chartTab === "Allocation" && (
              <div className="mt-[34px] flex flex-wrap items-center gap-4.5 text-xs text-[#8b9096]">
                {chartSeries.map((s) => (
                  <span key={s.id} className="inline-flex items-center gap-1.5">
                    <span className="size-2 shrink-0 rounded-full" style={{ backgroundColor: s.color }} />
                    {s.name}
                  </span>
                ))}
                <span className="inline-flex items-center gap-1.5">- - - Target</span>
              </div>
            )}

            {!hasActivity ? (
              <div className="mt-[34px] flex h-[210px] flex-col items-center justify-center border-t border-b border-[#22262b] text-center">
                <p className="text-[15px] font-medium text-white">No activity yet</p>
                <p className="mt-3 text-sm text-[#8b9096]">
                  Your {chartTab === "Allocation" ? "allocation history" : "routed volume"} will appear once routed
                  trades begin.
                </p>
              </div>
            ) : chartTab === "Allocation" ? (
              <div className="mt-3">
                <AllocationHistoryChart series={chartSeries} />
              </div>
            ) : (
              <div className="mt-[34px]">
                <VolumeBarChart bars={volumeSeries ?? []} />
              </div>
            )}
          </div>
        </div>

        <div className="mt-5 flex items-center justify-between">
          <p className="text-[26px] font-semibold text-white">
            Baskets <span className="font-normal text-[#8b9096]">({baskets.length}/{baskets.length})</span>
          </p>
          <div className="flex gap-3">
            <IconButton aria-label="Scroll baskets left" onClick={() => scrollBaskets(-1)}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M14 6l-6 6 6 6" />
              </svg>
            </IconButton>
            <IconButton aria-label="Scroll baskets right" onClick={() => scrollBaskets(1)}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M10 6l6 6-6 6" />
              </svg>
            </IconButton>
          </div>
        </div>

        <div ref={basketsRef} className="mt-4 flex gap-8 overflow-x-auto">
          {baskets.map((basket) => (
            <div key={basket.id} className="min-w-[500px] flex-1 rounded-[30px] border border-white/[0.03] bg-[#16181b] p-5">
              <div className="mb-4 flex items-start justify-between">
                <div className="flex items-center gap-3.5">
                  <TargetRing targetPct={basket.targetPct} color={basket.color} />
                  <div>
                    <p className="text-[19px] font-semibold text-white">{basket.name}</p>
                    <p className="mt-1 text-sm text-[#8b9096]">
                      {basket.tokens.length} tokens · {formatUsd(basket.managedValue)} managed
                    </p>
                  </div>
                </div>
                <div className="shrink-0 text-right">
                  <p className="text-[19px] font-semibold text-white">{basket.targetPct.toFixed(0)}%</p>
                  <p className="mt-1 text-sm text-[#8b9096]">Target allocation</p>
                </div>
              </div>
              <div className="overflow-hidden rounded-[24px] bg-[#1a1d21]">
                {basket.tokens.map((token) => (
                  <TokenListRow
                    key={token.address}
                    token={token}
                    balance={token.balance}
                    value={token.value}
                    readOnly
                    color={basket.color}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>

        <div className="mt-6 flex items-center justify-between">
          <p className="text-[26px] font-semibold text-white">Settings</p>
          {onUpdateStrategy && (
            <button
              type="button"
              onClick={onUpdateStrategy}
              className="flex h-12 items-center rounded-full bg-accent px-7 text-[15px] font-semibold text-[#0b0d10]"
            >
              Edit settings
            </button>
          )}
        </div>

        <div className="mt-4 flex flex-wrap gap-8">
          <div className="min-w-0 flex-1 basis-[500px] rounded-[30px] border border-white/[0.03] bg-[#16181b] p-6">
            <p className="mb-5 text-[13px] font-medium tracking-wide text-[#8b9096] uppercase">Baskets and Targets</p>
            {targetsRecap.map((basket) => (
              <div key={basket.id} className="mb-4.5 flex items-center justify-between gap-4 last:mb-0">
                <div>
                  <p className="text-sm font-medium text-white">{basket.name}</p>
                  <p className="mt-1.5 text-[13px] text-[#8b9096]">{basket.tokenSymbols.join(" · ")}</p>
                </div>
                <p className="text-[13px] font-medium text-white">{basket.targetPct.toFixed(1)}%</p>
              </div>
            ))}
          </div>
          <div className="min-w-0 flex-1 basis-[500px] rounded-[30px] border border-white/[0.03] bg-[#16181b] p-6">
            <p className="mb-5 text-[13px] font-medium tracking-wide text-[#8b9096] uppercase">Parameters</p>
            <div className="mb-4.5 flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-medium text-white">Price Deviation</p>
                <p className="mt-1.5 text-[13px] text-[#8b9096]">
                  Max. price difference allowed for routed transactions to execute.
                </p>
              </div>
              <p className="text-[13px] font-medium text-white">{priceDeviationPct}%</p>
            </div>
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-medium text-white">LP Fee</p>
                <p className="mt-1.5 text-[13px] text-[#8b9096]">
                  What you&apos;ll earn from each trade routed through your portfolio.
                </p>
              </div>
              <p className="text-[13px] font-medium text-white">{lpFeePct}%</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
