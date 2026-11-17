"use client";

import { AppHeader } from "@/components/AppHeader";
import { buildNavTabs } from "@/lib/navTabs";

const TABS = buildNavTabs("portfolio-manager");

export type PendingBasket = {
  id: string;
  name: string;
  tokenSymbols: string[];
  currentPct: number;
  currentValue: number;
  targetPct: number;
};

export type WaitingForSafeSignaturesPageProps = {
  network: string;
  safeAddress: string;
  signaturesRequired: number;
  signaturesCollected: number;
  transactionHash: string;
  priceDeviationPct: number;
  lpFeePct: number;
  baskets: PendingBasket[];
  onOpenInSafe?: () => void;
  onViewTransaction?: () => void;
};

const PENDING_SPINNER = (
  <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#8b9096" strokeWidth="1.4" strokeLinecap="round" aria-hidden="true">
    {Array.from({ length: 12 }, (_, i) => (
      <line key={i} x1="12" y1="2.5" x2="12" y2="5.5" opacity={0.25 + i * 0.06} transform={`rotate(${i * 30} 12 12)`} />
    ))}
  </svg>
);

const DONE_CHECK = (
  <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#8fc9d0" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M21 12a9 9 0 11-4-7.5" />
    <path d="M8 12l3 3 9-10" />
  </svg>
);

/** Reached after Review's "Agree and submit transaction" proposes the Safe transaction -- outside
 *  the 4-step wizard, so no WizardStepper here. Matches the Claude Artifact's own
 *  Pending_Sign.dc.html / Pending_Execute.dc.html exactly: a big "Your portfolio is about to get
 *  extra hands..." heading, a 2-step checklist (Activate Portfolio Manager → Execute Safe
 *  transaction, each either pending-spinner or done-check), and a Summary card mirroring Review's
 *  own Baskets-and-Targets/Parameters layout -- not the old single small centered card with a
 *  progress bar. The "execute" phase (step 1 already checked) is inferred from
 *  signaturesCollected >= signaturesRequired -- this app has no live polling of the Safe
 *  Transaction Service yet (see the route wrapper's own doc comment), so it can't show a
 *  mid-signing partial state beyond that threshold crossing. */
export function WaitingForSafeSignaturesPage({
  network,
  safeAddress,
  signaturesRequired,
  signaturesCollected,
  transactionHash,
  priceDeviationPct,
  lpFeePct,
  baskets,
  onOpenInSafe,
  onViewTransaction,
}: WaitingForSafeSignaturesPageProps) {
  const isExecutePhase = signaturesCollected >= signaturesRequired;
  const totalManagedValue = baskets.reduce((sum, b) => sum + b.currentValue, 0);

  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-[1284px] px-6 py-[70px]">
        <h1 className="mb-[30px] font-display text-4xl font-extrabold leading-tight text-white">
          Your portfolio is about to get extra hands...
        </h1>

        <div className="flex flex-wrap items-start gap-8">
          <div className="flex min-w-[320px] flex-1 flex-col gap-8">
            <div className="rounded-[32px] border border-white/[0.03] bg-[#16181b] p-6">
              <h2 className="text-[26px] font-semibold text-white">Transaction pending</h2>
              <p className="mt-2 text-[15px] text-[#8b9096]">Sign the transaction to activate your portfolio manager strategy.</p>
              <div className="my-7 h-px bg-[#262a2f]" />

              <div className="flex flex-col gap-5">
                <div className="flex items-center gap-4">
                  {isExecutePhase ? DONE_CHECK : PENDING_SPINNER}
                  <div>
                    <p className="text-base font-medium text-white">Activate Portfolio Manager</p>
                    {!isExecutePhase && (
                      <p className="mt-1 text-sm text-[#8b9096]">
                        Sign the transaction in your Safe wallet.{" "}
                        <span className="text-white">
                          (Signed {signaturesCollected}/{signaturesRequired})
                        </span>
                      </p>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  {PENDING_SPINNER}
                  <div>
                    <p className="text-base font-medium text-white">Execute Safe transaction</p>
                    {isExecutePhase && <p className="mt-1 text-sm text-[#8b9096]">Execute the transaction in your Safe wallet.</p>}
                  </div>
                </div>
              </div>
            </div>

            <div className="rounded-[32px] border border-white/[0.03] bg-[#16181b] p-6">
              <button
                type="button"
                onClick={onOpenInSafe}
                className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-gradient-to-b from-[#e3f3f5] to-[#8fc7cf] text-[15px] font-semibold text-[#0b0d10]"
              >
                Open in Safe
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M8 16L17 7M9 7h8v8" />
                </svg>
              </button>
              {transactionHash && (
                <button
                  type="button"
                  onClick={onViewTransaction}
                  className="mt-3 w-full text-center text-sm text-gray-500 hover:text-gray-300"
                >
                  View transaction
                </button>
              )}
            </div>
          </div>

          <div className="min-w-[320px] flex-1 rounded-[32px] border border-white/[0.03] bg-[#16181b] p-6">
            <h2 className="text-[26px] font-semibold text-white">Summary</h2>
            <div className="my-7 h-px bg-[#262a2f]" />

            <p className="mb-5 text-base text-[#8b9096]">Baskets and Targets</p>
            <div className="flex flex-col gap-[18px]">
              {baskets.map((basket) => {
                const targetValue = (basket.targetPct / 100) * totalManagedValue;
                return (
                  <div key={basket.id} className="flex items-start justify-between gap-4">
                    <div>
                      <p className="text-base font-medium text-white">{basket.name}</p>
                      <p className="mt-2 text-[13px] text-[#8b9096]">{basket.tokenSymbols.join(" · ")}</p>
                    </div>
                    <div className="shrink-0 text-right">
                      <p className="text-[13px] text-[#8b9096]">Current vs. Target allocation</p>
                      <p className="mt-1.5 text-[15px] font-semibold text-white">
                        {basket.currentPct.toFixed(0)}% <span className="text-[#8b9096]">→</span> {basket.targetPct.toFixed(0)}%
                      </p>
                      <p className="mt-1 text-xs text-[#8b9096]">
                        ${basket.currentValue.toLocaleString()} → ${targetValue.toLocaleString()}
                      </p>
                    </div>
                  </div>
                );
              })}
            </div>

            <div className="my-7 h-px bg-[#262a2f]" />

            <p className="mb-[18px] text-base text-[#8b9096]">Parameters</p>
            <div className="flex items-center justify-between text-base text-white">
              <span>Price deviation limit</span>
              <span>{priceDeviationPct}%</span>
            </div>
            <div className="mt-[18px] flex items-center justify-between text-base text-white">
              <span>LP fee tier</span>
              <span>{lpFeePct}%</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
