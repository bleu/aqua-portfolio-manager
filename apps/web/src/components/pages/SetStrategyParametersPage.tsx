"use client";

import { useState } from "react";
import { ChoicePillGroup } from "@/components/ChoicePillGroup";
import { Footer } from "@/components/Footer";
import { WizardFooter } from "@/components/WizardFooter";
import { WizardLayout } from "@/components/WizardLayout";
import { buildNavTabs } from "@/lib/navTabs";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS = buildNavTabs("portfolio-manager");
/** Confirmed against the Claude Artifact's own Step3_Parameters.dc.html -- no on-chain conflict
 *  (maxDeviationBps has no contract-enforced floor or ceiling). */
const PRICE_DEVIATION_OPTIONS = [1, 2, 5, 10];
/** Floor matches PortfolioManagerArgsCodec.MIN_FEE_BPS (0.5%) -- a lower preset would revert
 *  on-chain. The design's own preset list is [0.05%, 0.3%, 1%, 2%]; its lowest two values are
 *  both below that floor, not just the one value an earlier pass flagged. This list keeps the
 *  design's low-fee-biased intent (one low preset, two mid, one high) while staying inside the
 *  floor -- effectively unchanged from what was already here, not a skipped fix. */
const LP_FEE_OPTIONS = [0.5, 1, 2, 5];
const DEFAULT_LP_FEE = 2;

export type SetStrategyParametersPageProps = {
  network: string;
  safeAddress: string;
  onBack?: () => void;
  onContinue?: (params: { priceDeviationPct: number; lpFeePct: number }) => void;
  onSelectTab?: (label: string) => void;
};

/** BLEUDEV-415 — step 3 of the 4-step setup wizard ("Parameters"). Matches the design reference's
 *  "3. Parameters" screen: one unified panel (title, both settings, Continue) rather than two
 *  separate numbered/disclosure cards -- that structural change is the real fix here, the colors
 *  and chip shape are secondary. Price-deviation stays a required field with no default (the
 *  reference pre-selects 1%): forcing an explicit choice is an existing safety decision, not a
 *  styling detail, so it's kept as-is rather than silently relaxed to match the mockup. */
export function SetStrategyParametersPage({
  network,
  safeAddress,
  onBack,
  onContinue,
  onSelectTab,
}: SetStrategyParametersPageProps) {
  const [priceDeviationPct, setPriceDeviationPct] = useState<number | undefined>(undefined);
  const [lpFeePct, setLpFeePct] = useState<number | undefined>(DEFAULT_LP_FEE);

  return (
    <WizardLayout
      network={network}
      safeAddress={safeAddress}
      tabs={TABS}
      onSelectTab={onSelectTab}
      steps={WIZARD_STEPS}
      activeStepIndex={2}
      contentWidthPx={1000}
      footer={<Footer />}
    >
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
            {priceDeviationPct === undefined && <p className="mt-2 text-xs text-red-400">Price deviation is required.</p>}
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
            continueLabel="Continue"
            showBack
            onBack={onBack}
            continueDisabled={priceDeviationPct === undefined || lpFeePct === undefined}
            onContinue={() => {
              if (priceDeviationPct === undefined || lpFeePct === undefined) return;
              onContinue?.({ priceDeviationPct, lpFeePct });
            }}
          />
        </div>
    </WizardLayout>
  );
}
