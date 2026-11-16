"use client";

import { useMemo, useState } from "react";
import { AllocationPreviewBar } from "@/components/AllocationPreviewBar";
import { AppHeader } from "@/components/AppHeader";
import { Footer } from "@/components/Footer";
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

/** BLEUDEV-414 — "05 · Set target allocation": step 2 of the 4-step setup wizard. Matches
 *  Figma's own "2. Targets" flow screen (node 680:20768): one rounded standalone panel holding
 *  the title, column labels, basket rows, and allocation preview together -- not a separate
 *  heading/description/badge above a plain divided list, which is what this page looked like
 *  before. */
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

      <div className="mx-auto max-w-5xl px-6 py-8">
        <div className="mb-6">
          <WizardStepper steps={WIZARD_STEPS} activeIndex={1} />
        </div>

        <div className="flex flex-col gap-6 rounded-[30px] border border-border/60 bg-surface-card p-6">
          <div>
            <h1 className="text-2xl font-bold text-ink-primary">Set target allocation</h1>
            <p className="mt-1 text-base text-ink-muted">Set the share of the portfolio each basket should represent.</p>
          </div>

          <div className="h-px w-full bg-border" />

          <div className="flex items-center justify-between px-6 text-xs font-medium tracking-wide text-ink-muted uppercase">
            <span>Basket</span>
            <span>Current allocation</span>
            <span>Target</span>
          </div>

          <div className="flex flex-col gap-3">
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

          <div className="flex items-center justify-between text-xs font-medium text-ink-muted">
            <span>Allocation preview</span>
            <span className="text-[11px] font-normal">{total.toFixed(0)}%</span>
          </div>
          <AllocationPreviewBar
            baskets={baskets.map((b) => ({ id: b.id, name: b.name, color: b.color, targetPct: targets[b.id] }))}
            status={needsRebalance ? "Rebalance required" : "Matches current allocation → No initial rebalance"}
          />
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

      <Footer />
    </div>
  );
}
