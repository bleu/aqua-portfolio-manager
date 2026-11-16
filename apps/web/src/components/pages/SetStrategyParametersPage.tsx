"use client";

import { useState } from "react";
import { AppHeader } from "@/components/AppHeader";
import { ChoicePillGroup } from "@/components/ChoicePillGroup";
import { Footer } from "@/components/Footer";
import type { TabNavItem } from "@/components/TabNav";
import { WizardFooter } from "@/components/WizardFooter";
import { WizardStepper } from "@/components/WizardStepper";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];
const PRICE_DEVIATION_OPTIONS = [0.1, 0.5, 1, 2, 5];
/** Floor matches PortfolioManagerArgsCodec.MIN_FEE_BPS (0.5%) -- a lower preset would revert
 *  on-chain. The design reference's own preset list starts at 0.05%, below that floor -- not
 *  copied here for exactly that reason, not an oversight. */
const LP_FEE_OPTIONS = [0.5, 1, 2, 5];
const DEFAULT_LP_FEE = 2;

export type SetStrategyParametersPageProps = {
  network: string;
  safeAddress: string;
  onBack?: () => void;
  onContinue?: (params: { priceDeviationPct: number; lpFeePct: number }) => void;
};

/** BLEUDEV-415 — step 3 of the 4-step setup wizard ("Parameters"). Matches the design reference's
 *  "3. Parameters" screen: one unified panel (title, both settings, Continue) rather than two
 *  separate numbered/disclosure cards -- that structural change is the real fix here, the colors
 *  and chip shape are secondary. Price-deviation stays a required field with no default (the
 *  reference pre-selects 1%): forcing an explicit choice is an existing safety decision, not a
 *  styling detail, so it's kept as-is rather than silently relaxed to match the mockup. */
export function SetStrategyParametersPage({ network, safeAddress, onBack, onContinue }: SetStrategyParametersPageProps) {
  const [priceDeviationPct, setPriceDeviationPct] = useState<number | undefined>(undefined);
  const [lpFeePct, setLpFeePct] = useState<number | undefined>(DEFAULT_LP_FEE);

  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-5xl px-6 py-8">
        <div className="mt-6 mb-6">
          <WizardStepper steps={WIZARD_STEPS} activeIndex={2} />
        </div>

        <div className="rounded-[30px] border border-border/60 bg-surface-card p-6">
          <h1 className="text-2xl font-bold text-ink-primary">Set protection and fees</h1>
          <p className="mt-1 text-base text-ink-muted">
            Choose how strictly prices are protected and how much you&apos;ll charge per routed transaction.
          </p>

          <div className="my-7 h-px w-full bg-border" />

          <div>
            <h2 className="text-base font-semibold text-ink-primary">Price deviation limit</h2>
            <p className="mt-2 mb-4 text-sm text-ink-muted">
              Set the maximum price difference allowed for transactions to execute. A lower limit offers more
              protection but may delay execution.
            </p>
            <ChoicePillGroup options={PRICE_DEVIATION_OPTIONS} value={priceDeviationPct} onChange={setPriceDeviationPct} />
          </div>

          <div className="mt-9">
            <h2 className="text-base font-semibold text-ink-primary">Fee tier</h2>
            <p className="mt-2 mb-4 text-sm text-ink-muted">
              Set the fee you&apos;ll earn when trades are routed through your portfolio. Higher fees increase
              earnings per trade, but may attract fewer trades.
            </p>
            <ChoicePillGroup options={LP_FEE_OPTIONS} value={lpFeePct} onChange={setLpFeePct} />
          </div>
        </div>

        <div className="mt-6">
          <WizardFooter
            summary={`${priceDeviationPct !== undefined ? `Price deviation ${priceDeviationPct}%` : "Price deviation required"} · LP fee tier ${lpFeePct ?? "—"}%`}
            continueLabel="Continue to review"
            showBack
            onBack={onBack}
            continueDisabled={priceDeviationPct === undefined || lpFeePct === undefined}
            onContinue={() => {
              if (priceDeviationPct === undefined || lpFeePct === undefined) return;
              onContinue?.({ priceDeviationPct, lpFeePct });
            }}
          />
        </div>
      </div>

      <Footer />
    </div>
  );
}
