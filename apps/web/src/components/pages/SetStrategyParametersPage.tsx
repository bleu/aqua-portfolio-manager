"use client";

import { useState } from "react";
import { AppHeader } from "@/components/AppHeader";
import { Badge } from "@/components/Badge";
import { ChoicePillGroup } from "@/components/ChoicePillGroup";
import { Disclosure } from "@/components/Disclosure";
import { InfoBanner } from "@/components/InfoBanner";
import { NumberedStepCard } from "@/components/NumberedStepCard";
import type { TabNavItem } from "@/components/TabNav";
import { WizardFooter } from "@/components/WizardFooter";
import { WizardStepper } from "@/components/WizardStepper";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];
const PRICE_DEVIATION_OPTIONS = [0.1, 0.5, 1, 2, 5];
const LP_FEE_OPTIONS = [0.05, 0.3, 1, 2];
const DEFAULT_LP_FEE = 2;

export type SetStrategyParametersPageProps = {
  network: string;
  safeAddress: string;
  onBack?: () => void;
  onContinue?: (params: { priceDeviationPct: number; lpFeePct: number }) => void;
};

/** BLEUDEV-415 — step 3 of the 4-step setup wizard ("Parameters"). */
export function SetStrategyParametersPage({ network, safeAddress, onBack, onContinue }: SetStrategyParametersPageProps) {
  const [priceDeviationPct, setPriceDeviationPct] = useState<number | undefined>(undefined);
  const [lpFeePct, setLpFeePct] = useState<number | undefined>(DEFAULT_LP_FEE);


  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-3xl px-6 py-8">
        <h1 className="text-2xl font-semibold text-white">Set strategy parameters</h1>
        <p className="mt-1 text-sm text-gray-400">
          Choose how strictly prices are protected and how much the strategy charges per routed trade.
        </p>

        <div className="mt-6">
          <WizardStepper steps={WIZARD_STEPS} activeIndex={2} />
        </div>

        <div className="mt-8 space-y-4">
          <NumberedStepCard
            index={1}
            title="Set the price deviation limit"
            subtitle="Choose the maximum price difference allowed between the quoted price and the oracle price. Lower values provide stricter protection, but may cause more transactions to wait."
          >
            <div>
              <div className="flex items-center gap-2">
                <span className="text-sm text-gray-300">Choose a value</span>
                <Badge className="border-red-400/40 bg-red-400/10 text-red-300">Required</Badge>
              </div>
              <ChoicePillGroup
                className="mt-2"
                options={PRICE_DEVIATION_OPTIONS}
                value={priceDeviationPct}
                onChange={setPriceDeviationPct}
              />
              <p className="mt-2 text-xs text-gray-500">Minimum 0.1% · No maximum</p>
            </div>
            <Disclosure label="How price protection works">
              If the quoted price moves beyond this limit compared to the oracle price, the trade waits instead of
              executing at a worse rate.
            </Disclosure>
          </NumberedStepCard>

          <NumberedStepCard
            index={2}
            title="Set the LP fee tier"
            subtitle="Choose the fee collected from routed trades. Higher fees may earn more per trade, but can make the strategy less competitive for routing."
          >
            <div>
              <div className="flex items-center gap-2">
                <span className="text-sm text-gray-300">Choose a value</span>
                <Badge>Default</Badge>
              </div>
              <ChoicePillGroup className="mt-2" options={LP_FEE_OPTIONS} value={lpFeePct} onChange={setLpFeePct} />
              <p className="mt-2 text-xs text-gray-500">
                The protocol fee is deducted from the LP fee before earnings reach your Safe.
              </p>
            </div>
            <Disclosure label="View protocol fee calculation">
              The protocol takes a share of every routed trade&apos;s LP fee before the remainder reaches your Safe.
            </Disclosure>
          </NumberedStepCard>

          <InfoBanner>Both settings apply to the entire strategy.</InfoBanner>
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
    </div>
  );
}
