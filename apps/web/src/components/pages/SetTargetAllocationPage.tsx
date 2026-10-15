"use client";

import { useMemo, useState } from "react";
import { AllocationPreviewBar } from "@/components/AllocationPreviewBar";
import { AppHeader } from "@/components/AppHeader";
import { Badge } from "@/components/Badge";
import { InfoBanner } from "@/components/InfoBanner";
import { TargetAllocationRow } from "@/components/TargetAllocationRow";
import type { TabNavItem } from "@/components/TabNav";
import { WizardFooter } from "@/components/WizardFooter";
import { WizardStepper } from "@/components/WizardStepper";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];
const REBALANCE_EPSILON_PCT = 0.05;

export type TargetBasket = {
  id: string;
  name: string;
  color: string;
  tokenSymbols: string[];
  currentValue: number;
};

export type SetTargetAllocationPageProps = {
  network: string;
  safeAddress: string;
  baskets: TargetBasket[];
  onBack?: () => void;
  onContinue?: (targetsPct: Record<string, number>) => void;
};

function currentAllocationPct(baskets: TargetBasket[]): Record<string, number> {
  const total = baskets.reduce((sum, b) => sum + b.currentValue, 0);
  return Object.fromEntries(
    baskets.map((b) => [b.id, total > 0 ? (b.currentValue / total) * 100 : 100 / baskets.length]),
  );
}

/** Editing one basket's target redistributes the remainder across every other basket,
 *  proportionally to their current relative targets -- generalizes "changing one adjusts the
 *  other" from the 2-basket mockup to any number of baskets while always summing to 100. */
function applyTarget(targets: Record<string, number>, id: string, rawValue: number): Record<string, number> {
  const clamped = Math.min(100, Math.max(0, Number.isFinite(rawValue) ? rawValue : 0));
  const otherIds = Object.keys(targets).filter((k) => k !== id);
  const next = { ...targets, [id]: clamped };
  if (otherIds.length === 0) return next;

  const remainder = 100 - clamped;
  const othersSum = otherIds.reduce((sum, otherId) => sum + targets[otherId], 0);
  if (othersSum <= 0) {
    const even = remainder / otherIds.length;
    for (const otherId of otherIds) next[otherId] = even;
  } else {
    for (const otherId of otherIds) next[otherId] = (targets[otherId] / othersSum) * remainder;
  }
  return next;
}

/** BLEUDEV-414 — "05 · Set target allocation": step 2 of the 4-step setup wizard. */
export function SetTargetAllocationPage({ network, safeAddress, baskets, onBack, onContinue }: SetTargetAllocationPageProps) {
  const currentPct = useMemo(() => currentAllocationPct(baskets), [baskets]);
  const [targets, setTargets] = useState<Record<string, number>>(() => ({ ...currentPct }));

  const total = Object.values(targets).reduce((sum, v) => sum + v, 0);
  const needsRebalance = baskets.some((b) => Math.abs(targets[b.id] - currentPct[b.id]) > REBALANCE_EPSILON_PCT);

  function handleTargetChange(id: string, value: number) {
    setTargets((prev) => applyTarget(prev, id, value));
  }

  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-3xl px-6 py-8">
        <h1 className="text-2xl font-semibold text-white">Set target allocation</h1>
        <p className="mt-1 text-sm text-gray-400">Set the share of the portfolio each basket should represent.</p>

        <div className="mt-6">
          <WizardStepper steps={WIZARD_STEPS} activeIndex={1} />
        </div>

        <div className="mt-8 rounded-xl border border-border bg-surface-card p-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="text-lg font-semibold text-white">Target allocation</h2>
              <p className="mt-1 text-sm text-gray-400">Targets are prefilled from the portfolio&apos;s current allocation.</p>
            </div>
            <Badge className="shrink-0">
              Total <span className="font-semibold text-white">{total.toFixed(0)}%</span>
            </Badge>
          </div>

          <div className="mt-5 divide-y divide-border">
            <div className="flex items-center justify-between pb-2 text-[11px] font-medium tracking-wide text-gray-500 uppercase">
              <span>Basket</span>
              <span>Current allocation</span>
              <span>Target</span>
            </div>
            {baskets.map((basket) => (
              <TargetAllocationRow
                key={basket.id}
                name={basket.name}
                color={basket.color}
                tokenSymbols={basket.tokenSymbols}
                currentPct={currentPct[basket.id]}
                currentValue={basket.currentValue}
                targetPct={targets[basket.id]}
                onTargetChange={(value) => handleTargetChange(basket.id, value)}
              />
            ))}
          </div>

          <div className="mt-5">
            <InfoBanner>Changing one target adjusts the other so the total always stays at 100%.</InfoBanner>
          </div>

          <div className="mt-6">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-medium text-white">Allocation preview</h3>
              <Badge className="border-border bg-surface-raised text-gray-300">
                {needsRebalance ? "Rebalance required" : "Matches current allocation"}
              </Badge>
            </div>
            <AllocationPreviewBar
              className="mt-3"
              baskets={baskets.map((b) => ({ id: b.id, name: b.name, color: b.color, targetPct: targets[b.id] }))}
              noInitialRebalance={!needsRebalance}
            />
          </div>
        </div>

        <div className="mt-6">
          <WizardFooter
            summary={`Targets total ${total.toFixed(0)}% · ${needsRebalance ? "Rebalance required" : "No initial rebalance"}`}
            continueLabel="Continue to parameters"
            showBack
            onBack={onBack}
            onContinue={() => onContinue?.(targets)}
          />
        </div>
      </div>
    </div>
  );
}
