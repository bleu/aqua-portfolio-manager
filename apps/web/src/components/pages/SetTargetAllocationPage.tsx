"use client";

import { useMemo, useState } from "react";
import { AllocationPreviewBar } from "@/components/AllocationPreviewBar";
import { Footer } from "@/components/Footer";
import { TargetAllocationRow } from "@/components/TargetAllocationRow";
import { WizardFooter } from "@/components/WizardFooter";
import { WizardLayout } from "@/components/WizardLayout";
import { buildNavTabs } from "@/lib/navTabs";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS = buildNavTabs("portfolio-manager");
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
  onSelectTab?: (label: string) => void;
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

/** BLEUDEV-414 — "05 · Set target allocation": step 2 of the 4-step setup wizard. Matches the
 *  design reference's "2. Targets" / "Targets - rebalance required" screens: one rounded
 *  standalone panel holding the title, column labels, basket rows, and allocation preview
 *  together, plus a risk-acknowledgement gate that only appears once the chosen targets actually
 *  differ from the current allocation. */
export function SetTargetAllocationPage({
  network,
  safeAddress,
  baskets,
  onBack,
  onContinue,
  onSelectTab,
}: SetTargetAllocationPageProps) {
  const currentPct = useMemo(() => currentAllocationPct(baskets), [baskets]);
  const [targets, setTargets] = useState<Record<string, number>>(() => ({ ...currentPct }));
  const [riskAcknowledged, setRiskAcknowledged] = useState(false);

  const total = Object.values(targets).reduce((sum, v) => sum + v, 0);
  const needsRebalance = baskets.some((b) => Math.abs(targets[b.id] - currentPct[b.id]) > REBALANCE_EPSILON_PCT);

  function handleTargetChange(id: string, value: number) {
    setTargets((prev) => applyTarget(prev, id, value));
    // A later edit can turn a rebalance back into a match (or vice versa) -- re-acknowledging is
    // required either way, not carried over from a previous, different allocation.
    setRiskAcknowledged(false);
  }

  return (
    <WizardLayout
      network={network}
      safeAddress={safeAddress}
      tabs={TABS}
      onSelectTab={onSelectTab}
      steps={WIZARD_STEPS}
      activeStepIndex={1}
      contentWidthPx={1000}
      footer={<Footer />}
    >
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
            status={
              needsRebalance
                ? "Target is different from current allocation → Initial rebalance required"
                : "Matches current allocation → No initial rebalance"
            }
          />

          {needsRebalance && (
            <>
              <div className="flex items-start gap-4 rounded-[22px] border border-[#b79f6e] bg-[#14161a] p-5">
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#c9ad78" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="mt-1 shrink-0">
                  <path d="M12 4l9 16H3L12 4zM12 10v4M12 17v.5" />
                </svg>
                <div>
                  <p className="text-base font-semibold text-ink-primary">Initial rebalance required</p>
                  <p className="mt-1.5 text-sm text-[#c6cacd]">
                    Your target allocation differs from your current allocation. Creating this Portfolio Manager
                    will require an initial rebalance, which may expose your portfolio to losses.
                  </p>
                </div>
              </div>
              <label className="flex items-center gap-2.5 text-sm text-ink-primary">
                <input
                  type="checkbox"
                  checked={riskAcknowledged}
                  onChange={(e) => setRiskAcknowledged(e.target.checked)}
                  className="h-[22px] w-[22px] shrink-0 rounded border-border bg-surface-raised accent-accent"
                />
                I understand the risks and want to proceed with the initial rebalance.
              </label>
            </>
          )}
        </div>

        <div className="mt-6">
          <WizardFooter
            continueLabel="Continue"
            showBack
            onBack={onBack}
            onContinue={() => onContinue?.(targets)}
            continueDisabled={needsRebalance && !riskAcknowledged}
          />
        </div>
    </WizardLayout>
  );
}
