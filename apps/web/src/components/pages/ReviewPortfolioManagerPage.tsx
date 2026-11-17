"use client";

import { useState } from "react";
import { Disclosure } from "@/components/Disclosure";
import { WizardFooter } from "@/components/WizardFooter";
import { WizardLayout } from "@/components/WizardLayout";
import { truncateAddress } from "@/lib/format";
import { buildNavTabs } from "@/lib/navTabs";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS = buildNavTabs("portfolio-manager");
const REBALANCE_EPSILON_PCT = 0.05;

/** The exact copy the Claude Artifact's own Outcome_Blocked.dc.html uses -- the route wrapper
 *  (ReviewPageClient's describeCreateTransactionError) returns this literal string when the
 *  thrown error is PortfolioManagerSwapExcessivePriceDeviation/
 *  PortfolioManagerStrategyValidatorExcessivePriceDeviation, so this page can show the "blocked by
 *  price limit" outcome instead of a generic failure without the two files needing to duplicate
 *  the match pattern. */
export const PRICE_LIMIT_BLOCKED_MESSAGE =
  "The price exceeded your configured deviation limit, so the transaction wasn't executed. You can retry when prices are within your limit.";

export type ReviewBasket = {
  id: string;
  name: string;
  color: string;
  tokenSymbols: string[];
  currentPct: number;
  currentValue: number;
  targetPct: number;
};

/** One row of the transaction checklist below -- shipping a strategy is now a sequence of
 *  ordinary transactions (see src/lib/safeProposal.ts's own doc comment for why), not one bundled
 *  confirmation, so the page needs to show every step and which one is current, not just a single
 *  rotating status line. */
export type TransactionStep = {
  label: string;
  status: "pending" | "active" | "done" | "error";
};

/** A prior active strategy that would fail BasketScopeGuard.sol's own checks once the new baskets
 *  are declared -- see docs/adr/0011, this is the off-chain check the Guard itself can't perform
 *  retroactively against a Safe's event history. Mirrors the Guard's two revert reasons exactly:
 *  "cross-basket" (tokens split across more than one new basket) and "basket-foreign" (a token
 *  outside every new basket). A strategy can carry either reason, or both. */
export type ScopeConflictType = "cross-basket" | "basket-foreign";

export type ScopeConflict = {
  strategyHash: string;
  app: string;
  types: ScopeConflictType[];
  basketNames: string[];
  foreignTokens: string[];
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
  isCreatingTransaction?: boolean;
  createTransactionError?: string;
  /** The full step list, shown once "Submit transaction" is clicked (before that, this page shows
   *  no steps at all -- nothing has started yet). */
  transactionSteps?: TransactionStep[];
  /** Non-empty blocks submission entirely -- see ScopeConflict's doc comment. */
  scopeConflicts?: ScopeConflict[];
  scopeConflictCheckError?: string;
  /** True blocks submission entirely -- Aqua.ship() permanently refuses to reuse a strategyHash
   *  once shipped, even after docking (Aqua.sol's StrategiesMustBeImmutable), and the hash has no
   *  nonce, so these exact parameters can never ship again. */
  alreadyShipped?: boolean;
  alreadyShippedCheckError?: string;
};

/** BLEUDEV-416 — step 4 of the 4-step setup wizard ("Review"). Matches the Claude Artifact's own
 *  Step4_Review.dc.html / Step4_Risk_Modal.dc.html exactly: no ring icons on the basket rows (just
 *  a current%→target% / $→$ comparison), a "Parameters" section instead of "Transaction details"
 *  (Safe/Network dropped -- already in the header), a separate action-bar card instead of buttons
 *  inside the content card, and a risk-acknowledgement modal gating the real submit. */
export function ReviewPortfolioManagerPage({
  network,
  safeAddress,
  baskets,
  priceDeviationPct,
  lpFeePct,
  signaturesRequired,
  onBack,
  onCreateTransaction,
  isCreatingTransaction,
  createTransactionError,
  transactionSteps,
  scopeConflicts,
  scopeConflictCheckError,
  alreadyShipped,
  alreadyShippedCheckError,
}: ReviewPortfolioManagerPageProps) {
  const [showRiskModal, setShowRiskModal] = useState(false);
  const [dismissedOutcomeError, setDismissedOutcomeError] = useState<string>();
  const needsRebalance = baskets.some((b) => Math.abs(b.currentPct - b.targetPct) > REBALANCE_EPSILON_PCT);
  const hasScopeConflict = !!scopeConflicts && scopeConflicts.length > 0;
  const blocked = hasScopeConflict || alreadyShipped;
  // Purely a display derivation from props already passed (the same sum the review route itself
  // computes as "total" for currentPct) -- not a new balance/price read.
  const totalManagedValue = baskets.reduce((sum, b) => sum + b.currentValue, 0);

  function handleSubmitClick() {
    if (blocked || isCreatingTransaction) return;
    setShowRiskModal(true);
  }

  function handleAgreeAndSubmit() {
    setShowRiskModal(false);
    onCreateTransaction?.();
  }

  return (
    <WizardLayout
      network={network}
      safeAddress={safeAddress}
      tabs={TABS}
      steps={WIZARD_STEPS}
      activeStepIndex={3}
      contentWidthPx={700}
    >
      <div className="flex flex-col gap-6">
        <div className="rounded-[28px] border border-white/[0.03] bg-[#16181b] p-6">
          <h1 className="text-2xl font-semibold text-white">Review your portfolio manager</h1>
          <p className="mt-2 text-[15px] text-[#8b9096]">
            Check the details before activating your portfolio manager strategy.
          </p>

          <div className="my-7 h-px bg-[#262a2f]" />

          <p className="mb-5 text-base text-[#8b9096]">Baskets and Targets</p>
          <div className="flex flex-col gap-[22px]">
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

          <div className="mt-5 flex items-center gap-2 text-sm text-gray-400">
            <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${needsRebalance ? "bg-amber-400" : "bg-positive"}`} />
            {needsRebalance ? "Initial rebalance required" : "No initial rebalance expected"}
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
          {signaturesRequired > 0 && (
            <div className="mt-[18px] flex items-center justify-between text-base text-white">
              <span>Signatures required</span>
              <span>{signaturesRequired}</span>
            </div>
          )}

          <div className="mt-5">
            <Disclosure label="View fees and permissions">
              The protocol takes a share of every routed trade&apos;s LP fee, and this strategy can only trade the
              tokens declared in its baskets.
            </Disclosure>
          </div>

          {transactionSteps && transactionSteps.length > 0 && (
            <div className="mt-6 border-t border-border pt-4">
              <p className="text-[11px] font-medium tracking-wide text-gray-500 uppercase">Transaction steps</p>
              <ul className="mt-2 space-y-2">
                {transactionSteps.map((step, i) => (
                  <li key={i} className="flex items-center gap-2 text-sm">
                    <StepStatusDot status={step.status} />
                    <span
                      className={
                        step.status === "pending"
                          ? "text-gray-500"
                          : step.status === "error"
                            ? "text-red-300"
                            : "text-gray-200"
                      }
                    >
                      {step.label}
                    </span>
                    {step.status === "active" && (
                      <span className="text-xs text-gray-500">— check your wallet for a signature request</span>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {hasScopeConflict && (
            <div className="mt-4 rounded-lg border border-red-400/40 bg-red-400/10 p-3 text-sm text-red-300">
              <p className="font-medium">
                This Safe already has {scopeConflicts!.length === 1 ? "an incompatible strategy" : "incompatible strategies"}
              </p>
              <p className="mt-1 text-red-300/90">
                Creating this Portfolio Manager won&apos;t stop the strategy below, so it can&apos;t actually keep
                your baskets separate. Dock it first, or redraw your baskets so it fits inside one.
              </p>
              <ul className="mt-2 space-y-2">
                {scopeConflicts!.map((conflict) => (
                  <li key={conflict.strategyHash} className="rounded-md border border-red-400/30 bg-red-400/5 p-2">
                    <p className="font-mono text-xs text-red-300/80">
                      Strategy {truncateAddress(conflict.strategyHash)} (app {truncateAddress(conflict.app)})
                    </p>
                    {conflict.types.includes("cross-basket") && (
                      <p className="mt-1">
                        <span className="rounded bg-red-400/20 px-1.5 py-0.5 text-[11px] font-medium uppercase">
                          cross-basket
                        </span>{" "}
                        Trades across {conflict.basketNames.length} separate baskets ({conflict.basketNames.join(", ")})
                        -- the Guard only allows this for its own Portfolio Manager strategy.
                      </p>
                    )}
                    {conflict.types.includes("basket-foreign") && (
                      <p className="mt-1">
                        <span className="rounded bg-red-400/20 px-1.5 py-0.5 text-[11px] font-medium uppercase">
                          basket-foreign
                        </span>{" "}
                        Holds {conflict.foreignTokens.length === 1 ? "a token" : "tokens"} (
                        {conflict.foreignTokens.map((t) => truncateAddress(t)).join(", ")}) that{" "}
                        {conflict.foreignTokens.length === 1 ? "isn't" : "aren't"} declared in any of your baskets.
                      </p>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {scopeConflictCheckError && (
            <p className="mt-4 rounded-lg border border-amber-400/40 bg-amber-400/10 p-3 text-sm text-amber-300">
              {scopeConflictCheckError} You can still proceed, but this Safe hasn&apos;t been checked for conflicting
              prior strategies.
            </p>
          )}

          {alreadyShipped && (
            <div className="mt-4 rounded-lg border border-red-400/40 bg-red-400/10 p-3 text-sm text-red-300">
              <p className="font-medium">This exact strategy has already been shipped before</p>
              <p className="mt-1 text-red-300/90">
                Once a strategy with these exact baskets, fee, and price deviation ships, it can never ship
                again -- even after being deleted. Change the LP fee, price deviation, or baskets slightly to
                create a new one.
              </p>
            </div>
          )}

          {alreadyShippedCheckError && (
            <p className="mt-4 rounded-lg border border-amber-400/40 bg-amber-400/10 p-3 text-sm text-amber-300">
              {alreadyShippedCheckError} You can still proceed, but this strategy hasn&apos;t been checked against
              ones already shipped.
            </p>
          )}

        </div>

        <WizardFooter
          continueLabel={isCreatingTransaction ? "Submitting…" : "Submit transaction"}
          showBack
          onBack={onBack}
          backDisabled={isCreatingTransaction}
          onContinue={handleSubmitClick}
          continueDisabled={!!blocked || !!isCreatingTransaction}
        />
      </div>

      {showRiskModal && (
        <RiskWarningModal onClose={() => setShowRiskModal(false)} onAgree={handleAgreeAndSubmit} />
      )}

      {createTransactionError && createTransactionError !== dismissedOutcomeError && (
        <TransactionOutcomeModal
          key={createTransactionError}
          variant={createTransactionError === PRICE_LIMIT_BLOCKED_MESSAGE ? "blocked" : "failed"}
          baskets={baskets}
          priceDeviationPct={priceDeviationPct}
          lpFeePct={lpFeePct}
          totalManagedValue={totalManagedValue}
          onCancel={() => setDismissedOutcomeError(createTransactionError)}
          onRetry={() => {
            setDismissedOutcomeError(undefined);
            handleSubmitClick();
          }}
        />
      )}
    </WizardLayout>
  );
}

function StepStatusDot({ status }: { status: TransactionStep["status"] }) {
  if (status === "done") {
    return (
      <span className="flex size-4 shrink-0 items-center justify-center rounded-full border border-positive/50 bg-positive/10 text-[10px] text-positive">
        ✓
      </span>
    );
  }
  if (status === "error") {
    return (
      <span className="flex size-4 shrink-0 items-center justify-center rounded-full border border-red-400/50 bg-red-400/10 text-[10px] text-red-400">
        ✕
      </span>
    );
  }
  if (status === "active") {
    return <span className="size-2 shrink-0 animate-pulse rounded-full bg-accent" />;
  }
  return <span className="size-2 shrink-0 rounded-full border border-border" />;
}

/** The pre-submit risk-acknowledgement gate -- copy and layout confirmed directly against the
 *  Claude Artifact's project/Step4_Risk_Modal.dc.html (the 4 "avoid" bullets are its own text,
 *  not placeholders). The real transaction only fires from the "Agree and submit transaction"
 *  button, never from "Submit transaction" alone. */
function RiskWarningModal({ onClose, onAgree }: { onClose: () => void; onAgree: () => void }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#050608]/[0.72] p-6">
      <div className="w-full max-w-[596px] rounded-[32px] border border-[#2a2e33] bg-[#101316] p-6">
        <div className="flex items-start justify-between">
          <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="#c9ad78" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M12 4l9 16H3L12 4zM12 10v4M12 17v.5" />
          </svg>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="flex size-10 shrink-0 items-center justify-center rounded-full bg-[#1f2327] text-gray-300 hover:text-white"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          </button>
        </div>

        <p className="mt-6 mb-4 text-xl font-semibold text-white">
          Beware of actions that may disrupt your Portfolio Manager
        </p>
        <p className="mb-4 text-[15px] leading-[1.45] text-[#c6cacd]">
          The actions below can lead to significant losses as your Portfolio Manager continues to rebalance toward
          your targets.
        </p>
        <div className="text-[15px] leading-[1.45] text-[#c6cacd]">
          While your Portfolio Manager is active, avoid:
          <ul className="mt-1 list-disc pl-5">
            <li>Using strategies outside this Portfolio Manager.</li>
            <li>Using strategies that trade between different asset groups.</li>
            <li>Swapping tokens between different asset groups.</li>
            <li>Sending or receiving tokens included in this Portfolio Manager.</li>
          </ul>
        </div>

        <button
          type="button"
          onClick={onAgree}
          className="mt-[30px] flex h-12 w-full items-center justify-center rounded-full text-[15px] font-semibold text-[#0b0d10]"
          style={{ background: "linear-gradient(180deg,#f2eadb 0%,#c8ad7c 100%)" }}
        >
          Agree and submit transaction
        </button>
      </div>
    </div>
  );
}

/** The submission-didn't-go-through outcome, confirmed against the Claude Artifact's own
 *  project/Outcome_Failed.dc.html and Outcome_Blocked.dc.html -- structurally identical (same
 *  558px modal, same baskets/parameters recap, same Cancel/Retry pair), only the heading, body
 *  copy, and icon tint differ between a generic failure and a price-limit block. */
function TransactionOutcomeModal({
  variant,
  baskets,
  priceDeviationPct,
  lpFeePct,
  totalManagedValue,
  onCancel,
  onRetry,
}: {
  variant: "failed" | "blocked";
  baskets: ReviewBasket[];
  priceDeviationPct: number;
  lpFeePct: number;
  totalManagedValue: number;
  onCancel?: () => void;
  onRetry?: () => void;
}) {
  const heading = variant === "blocked" ? "Transaction blocked by price limit" : "Transaction failed";
  const body =
    variant === "blocked"
      ? PRICE_LIMIT_BLOCKED_MESSAGE
      : "Your Portfolio Manager wasn't activated. Try again.";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#050608]/[0.72] p-6">
      <div
        className="w-full max-w-[558px] rounded-[36px] border border-[#26292e] p-[30px_32px_32px] text-center"
        style={{ background: "linear-gradient(180deg,#1e1d21 0%,#111316 24%)" }}
      >
        <svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke={variant === "blocked" ? "#c9ad78" : "#e5483f"} strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="mx-auto">
          <circle cx="12" cy="12" r="9" />
          <path d="M12 8v5M12 16v.5" />
        </svg>
        <p className="mt-6 mb-3.5 text-2xl font-bold text-white">{heading}</p>
        <p className="mx-auto mb-6 text-[15px] leading-[1.4] text-[#c6cacd]">{body}</p>

        <div className="border-t border-[#262a2f] pt-6 text-left">
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

          <div className="my-[22px] h-px bg-[#262a2f]" />

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

        <div className="mt-[30px] flex gap-4">
          <button
            type="button"
            onClick={onCancel}
            className="flex h-12 flex-1 items-center justify-center rounded-full bg-[#1c2024] text-[15px] font-semibold text-white"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onRetry}
            className="flex h-12 flex-1 items-center justify-center rounded-full text-[15px] font-semibold text-[#0b0d10]"
            style={{ background: "linear-gradient(180deg,#e3f3f5 0%,#8fc7cf 100%)" }}
          >
            Retry
          </button>
        </div>
      </div>
    </div>
  );
}
