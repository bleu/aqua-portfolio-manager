"use client";

import { useState } from "react";
import { AllocationHistoryChart, type AllocationHistorySeries } from "@/components/AllocationHistoryChart";
import { AppHeader } from "@/components/AppHeader";
import { Badge } from "@/components/Badge";
import { Button } from "@/components/Button";
import { IconButton } from "@/components/IconButton";
import { MetricRow } from "@/components/MetricRow";
import { ProgressBar } from "@/components/ProgressBar";
import { SegmentedControl } from "@/components/SegmentedControl";
import type { TabNavItem } from "@/components/TabNav";
import { TokenListRow } from "@/components/TokenListRow";
import { MoreIcon } from "@/components/icons";
import { cn } from "@/lib/cn";
import { formatRelativeTime, formatUsd, truncateAddress } from "@/lib/format";

const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];
const TIME_RANGES = ["24h", "7d", "30d", "90d", "All"] as const;
type TimeRange = (typeof TIME_RANGES)[number];

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
  onUpdateStrategy?: () => void;
};

/** BLEUDEV-419 — the real-data counterpart to EmptyDashboardPage (BLEUDEV-410), shown at the same
 *  /dashboard route once the connected Safe has an active strategy. */
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
  onUpdateStrategy,
}: ActivePortfolioManagerDashboardPageProps) {
  const [range, setRange] = useState<TimeRange>("30d");

  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-6xl px-6 py-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold text-white">Portfolio Manager</h1>
              <Badge className="border-positive/40 bg-positive/10 text-positive" dotColor="#22c55e">
                Active
              </Badge>
            </div>
            <p className="mt-1 text-sm text-gray-500">
              {truncateAddress(safeAddress)} · {network} · Updated {formatRelativeTime(updatedAt)}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="accent" onClick={onUpdateStrategy}>
              Update strategy
            </Button>
            <IconButton aria-label="More options">
              <MoreIcon className="size-4" />
            </IconButton>
          </div>
        </div>

        <div className="mt-6 grid gap-4 lg:grid-cols-2">
          <div className="rounded-xl border border-border bg-surface-card p-6">
            <div className="flex items-start justify-between">
              <h2 className="text-lg font-semibold text-white">Portfolio overview</h2>
              <Badge className="border-accent/40 bg-accent/10 text-accent">{range}</Badge>
            </div>
            <div className="mt-4">
              <MetricRow
                label="Total managed value"
                value={formatUsd(managedValue)}
                caption="Assets managed by this Portfolio Manager"
                size="large"
              />
              <div className="mt-4 space-y-4">
                <MetricRow label="Net LP fees earned" value={formatUsd(netLpFeesEarned)} caption="After protocol fee" divider />
                <MetricRow
                  label="Routed volume"
                  value={formatUsd(routedVolume)}
                  caption={`${routedTransactionCount} transactions`}
                  divider
                />
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-border bg-surface-card p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 className="text-lg font-semibold text-white">Allocation history</h2>
                <p className="mt-1 text-sm text-gray-400">Current basket share compared with fixed targets</p>
              </div>
              <SegmentedControl options={TIME_RANGES} value={range} onChange={setRange} />
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-4">
              {chartSeries.map((s) => (
                <span key={s.id} className="inline-flex items-center gap-2 text-sm text-gray-400">
                  <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: s.color }} />
                  {s.name}
                </span>
              ))}
              <span className="inline-flex items-center gap-2 text-sm text-gray-400">
                <span className="h-px w-4 shrink-0 bg-gray-500" />
                Target
              </span>
            </div>
            <AllocationHistoryChart series={chartSeries} />
          </div>
        </div>

        <div className="mt-8 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-white">Basket composition</h2>
          <p className="text-xs text-gray-500">All selected token balances are managed</p>
        </div>

        <div className="mt-4 grid gap-4 lg:grid-cols-2">
          {baskets.map((basket) => (
            <div key={basket.id} className="rounded-xl border border-border bg-surface-card p-5">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <h3 className="font-semibold text-white">{basket.name}</h3>
                  <p className="mt-0.5 text-xs text-gray-500">{formatUsd(basket.managedValue)} managed</p>
                </div>
                <div className="flex gap-4 text-right">
                  <div>
                    <p className={cn("font-semibold")} style={{ color: basket.color }}>
                      {basket.currentPct.toFixed(1)}%
                    </p>
                    <p className="text-xs text-gray-500">Current</p>
                  </div>
                  <div>
                    <p className="font-semibold text-white">{basket.targetPct.toFixed(1)}%</p>
                    <p className="text-xs text-gray-500">Target</p>
                  </div>
                </div>
              </div>
              <ProgressBar value={basket.currentPct / 100} color={basket.color} className="mt-3" />
              <div className="mt-3 divide-y divide-border">
                {basket.tokens.map((token) => (
                  <TokenListRow
                    key={token.address}
                    token={token}
                    balance={token.balance}
                    value={token.value}
                    readOnly
                    tokenName={token.name}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
