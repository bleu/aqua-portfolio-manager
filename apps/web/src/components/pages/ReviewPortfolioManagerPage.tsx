"use client";

import { AppHeader } from "@/components/AppHeader";
import { Button } from "@/components/Button";
import { DetailRow } from "@/components/DetailRow";
import { Disclosure } from "@/components/Disclosure";
import { TargetAllocationRow } from "@/components/TargetAllocationRow";
import type { TabNavItem } from "@/components/TabNav";
import { WizardStepper } from "@/components/WizardStepper";
import { truncateAddress } from "@/lib/format";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];
const REBALANCE_EPSILON_PCT = 0.05;

export type ReviewBasket = {
  id: string;
  name: string;
  color: string;
  tokenSymbols: string[];
  currentPct: number;
  currentValue: number;
  targetPct: number;
};

export type ReviewPortfolioManagerPageProps = {
  network: string;
  safeAddress: string;
  baskets: ReviewBasket[];
  priceDeviationPct: number;
  lpFeePct: number;
  signaturesRequired: number;
  onBack?: () => void;
  onCreateTransaction?: () => void;
};

/** BLEUDEV-416 — step 4 of the 4-step setup wizard ("Review"). */
export function ReviewPortfolioManagerPage({
  network,
  safeAddress,
  baskets,
  priceDeviationPct,
  lpFeePct,
  signaturesRequired,
  onBack,
  onCreateTransaction,
}: ReviewPortfolioManagerPageProps) {
  const needsRebalance = baskets.some((b) => Math.abs(b.currentPct - b.targetPct) > REBALANCE_EPSILON_PCT);

  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-3xl px-6 py-8">
        <div className="mt-2 flex justify-center">
          <WizardStepper steps={WIZARD_STEPS} activeIndex={3} />
        </div>

        <div className="mt-8 rounded-xl border border-border bg-surface-card p-6">
          <h1 className="text-xl font-semibold text-white">Review Portfolio Manager</h1>
          <p className="mt-1 text-sm text-gray-400">Check the details before creating the Safe transaction.</p>

          <div className="mt-6">
            <p className="text-[11px] font-medium tracking-wide text-gray-500 uppercase">Baskets and targets</p>
            <div className="mt-2 divide-y divide-border">
              {baskets.map((basket) => (
                <TargetAllocationRow
                  key={basket.id}
                  name={basket.name}
                  color={basket.color}
                  tokenSymbols={basket.tokenSymbols}
                  currentPct={basket.currentPct}
                  currentValue={basket.currentValue}
                  targetPct={basket.targetPct}
                  readOnly
                />
              ))}
            </div>
            <div className="mt-2 flex items-center gap-2 text-sm text-gray-400">
              <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${needsRebalance ? "bg-amber-400" : "bg-positive"}`} />
              {needsRebalance ? "Initial rebalance expected" : "No initial rebalance expected"}
            </div>
          </div>

          <div className="mt-6 border-t border-border pt-4">
            <p className="text-[11px] font-medium tracking-wide text-gray-500 uppercase">Transaction details</p>
            <div className="mt-2">
              <DetailRow label="Price deviation" value={`${priceDeviationPct}%`} />
              <DetailRow label="LP fee tier" value={`${lpFeePct}%`} />
              <DetailRow label="Safe" value={truncateAddress(safeAddress)} />
              <DetailRow label="Network" value={network} />
              <DetailRow label="Signatures required" value={signaturesRequired} />
            </div>
            <div className="mt-3">
              <Disclosure label="View fees and permissions">
                The protocol takes a share of every routed trade&apos;s LP fee, and this strategy can only trade the
                tokens declared in its baskets.
              </Disclosure>
            </div>
          </div>

          <div className="mt-6 flex items-center justify-between gap-3">
            <Button variant="secondary" onClick={onBack}>
              Back
            </Button>
            <Button variant="accent" onClick={onCreateTransaction} className="flex-1">
              Create transaction
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
