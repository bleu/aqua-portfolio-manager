"use client";

import { useState } from "react";
import { Button } from "@/components/Button";

const ACTIONS = [
  {
    icon: "/welcome-choose-exposure.svg",
    title: "Choose your exposure",
    description: "Set the target allocation for each asset group.",
  },
  {
    icon: "/welcome-full-picture.svg",
    title: "See the full picture",
    description: "Track your net exposure across Aqua strategies in one place.",
  },
  {
    icon: "/welcome-rebalance.svg",
    title: "Rebalance automatically",
    description: "Let Trim direct trades toward your targets as your capital works across strategies.",
  },
  {
    icon: "/welcome-earn-fees.svg",
    title: "Earn fees",
    description: "Collect fees when trades use your liquidity.",
  },
];

export type WelcomeModalProps = {
  onContinue: () => void;
};

/** BLEUDEV-? — "Welcome to Trim" onboarding modal, shown once per Safe over a blurred backdrop
 *  before the setup wizard's first step, replacing the old dedicated empty-dashboard screen. */
export function WelcomeModal({ onContinue }: WelcomeModalProps) {
  const [agreed, setAgreed] = useState(true);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-[10px]">
      <div className="flex w-[717px] max-w-[calc(100%-2rem)] flex-col items-center gap-6 rounded-[30px] border border-border bg-surface-card p-6">
        <img src="/welcome-hero.svg" alt="" className="h-[159px] w-[165px]" />

        <div className="flex flex-col items-center gap-1 text-center">
          <h2 className="text-2xl font-bold text-ink-primary">Welcome to Trim</h2>
          <p className="text-[15px] text-ink-secondary">A few extra hands to keep your DeFi exposure in check.</p>
        </div>

        <div className="flex w-full flex-col gap-2">
          {ACTIONS.map((action) => (
            <div
              key={action.title}
              className="flex w-full items-center gap-3 rounded-[17px] bg-gradient-to-r from-white/[0.02] to-white/[0.04] p-3.5"
            >
              <img src={action.icon} alt="" className="h-8 w-8 shrink-0" />
              <div className="flex flex-1 flex-col gap-1">
                <p className="text-[15px] font-semibold text-[#f6f7f9]">{action.title}</p>
                <p className="text-[13px] text-[#aab2b9]">{action.description}</p>
              </div>
            </div>
          ))}
        </div>

        <label className="flex w-full items-center gap-2 text-sm text-ink-primary">
          <input
            type="checkbox"
            checked={agreed}
            onChange={(e) => setAgreed(e.target.checked)}
            className="h-4 w-4 shrink-0 rounded border-border bg-surface-raised accent-accent"
          />
          {/* No Terms of Use page exists yet -- this links nowhere until one does. */}
          <span>
            I agree to the{" "}
            <a href="#" className="text-accent underline">
              Terms of Use.
            </a>
          </span>
        </label>

        <Button variant="accent" className="w-full" disabled={!agreed} onClick={onContinue}>
          Continue
        </Button>
      </div>
    </div>
  );
}
