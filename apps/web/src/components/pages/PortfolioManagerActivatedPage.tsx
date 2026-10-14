"use client";

import { AppHeader } from "@/components/AppHeader";
import { Badge } from "@/components/Badge";
import { Button } from "@/components/Button";
import { NumberedStepCard } from "@/components/NumberedStepCard";
import { StatColumn } from "@/components/StatColumn";
import { StatusIcon } from "@/components/StatusIcon";
import type { TabNavItem } from "@/components/TabNav";
import { formatUsd, truncateAddress } from "@/lib/format";

const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];

const EXPLAINER_STEPS = [
  {
    title: "Routing runs automatically",
    subtitle: "Eligible trades continuously move the portfolio toward its basket targets.",
  },
  {
    title: "LP fees accumulate",
    subtitle: "Your dashboard shows the net LP fees earned after the protocol fee.",
  },
  {
    title: "Activity stays visible",
    subtitle: "Every routed transaction is recorded in the Portfolio Manager history.",
  },
];

export type ActivatedBasket = {
  id: string;
  name: string;
  color: string;
  tokenSymbols: string[];
  currentPct: number;
};

export type PortfolioManagerActivatedPageProps = {
  network: string;
  safeAddress: string;
  managedValue: number;
  baskets: ActivatedBasket[];
  tokenCount: number;
  lpFeePct: number;
  activationTxHash: string;
  onGoToDashboard?: () => void;
};

/** Terminal success page of the whole "create a strategy" flow, reached once the Safe
 *  transaction from BLEUDEV-417 actually executes. */
export function PortfolioManagerActivatedPage({
  network,
  safeAddress,
  managedValue,
  baskets,
  tokenCount,
  lpFeePct,
  activationTxHash,
  onGoToDashboard,
}: PortfolioManagerActivatedPageProps) {
  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto mt-16 max-w-2xl px-6 text-center">
        <StatusIcon variant="success" className="mx-auto" />
        <h1 className="mt-4 text-2xl font-bold text-white">Portfolio Manager activated</h1>
        <p className="mt-2 text-sm text-gray-400">
          Your strategy is active. Aqua routing can now rebalance the portfolio and generate LP fees from eligible
          trades.
        </p>

        <div className="mt-6 rounded-xl border border-border bg-surface-card p-6 text-left">
          <div className="flex justify-center">
            <Badge className="border-positive/40 bg-positive/10 text-positive" dotColor="#22c55e">
              Strategy active
            </Badge>
          </div>

          <div className="mt-5 grid grid-cols-4 gap-4">
            <StatColumn value={formatUsd(managedValue)} label="Managed value" />
            <StatColumn value={String(baskets.length)} label="Baskets" />
            <StatColumn value={String(tokenCount)} label="Tokens" />
            <StatColumn value={`${lpFeePct}%`} label="LP fee tier" />
          </div>

          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            {baskets.map((basket) => (
              <div key={basket.id} className="rounded-lg border border-border bg-surface-raised px-4 py-3">
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: basket.color }} />
                    <span className="font-medium text-white">{basket.name}</span>
                  </div>
                  <span className="font-semibold" style={{ color: basket.color }}>
                    {basket.currentPct.toFixed(1)}%
                  </span>
                </div>
                <p className="mt-0.5 pl-4 text-xs text-gray-500">{basket.tokenSymbols.join(" · ")}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="mt-6 grid gap-4 sm:grid-cols-3">
          {EXPLAINER_STEPS.map((step, i) => (
            <NumberedStepCard key={step.title} index={i + 1} title={step.title} subtitle={step.subtitle} />
          ))}
        </div>

        <Button variant="accent" className="mt-6" onClick={onGoToDashboard}>
          Go to dashboard
        </Button>
        <p className="mt-3 text-xs text-gray-500">Activation transaction · {truncateAddress(activationTxHash)}</p>
      </div>
    </div>
  );
}
