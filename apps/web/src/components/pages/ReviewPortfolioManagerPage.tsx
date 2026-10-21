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
  /** The full step list, shown once "Create transaction" is clicked (before that, this page shows
   *  no steps at all -- nothing has started yet). */
  transactionSteps?: TransactionStep[];
  /** Non-empty blocks "Create transaction" entirely -- see ScopeConflict's doc comment. */
  scopeConflicts?: ScopeConflict[];
  scopeConflictCheckError?: string;
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
  isCreatingTransaction,
  createTransactionError,
  transactionSteps,
  scopeConflicts,
  scopeConflictCheckError,
}: ReviewPortfolioManagerPageProps) {
  const needsRebalance = baskets.some((b) => Math.abs(b.currentPct - b.targetPct) > REBALANCE_EPSILON_PCT);
  const hasScopeConflict = !!scopeConflicts && scopeConflicts.length > 0;

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

          {createTransactionError && (
            <p className="mt-4 rounded-lg border border-red-400/40 bg-red-400/10 p-3 text-sm text-red-300">
              {createTransactionError}
            </p>
          )}

          <div className="mt-6 flex items-center justify-between gap-3">
            <Button variant="secondary" onClick={onBack} disabled={isCreatingTransaction}>
              Back
            </Button>
            <Button
              variant="accent"
              onClick={onCreateTransaction}
              disabled={isCreatingTransaction || hasScopeConflict}
              className="flex-1"
            >
              {isCreatingTransaction ? "Creating transaction…" : "Create transaction"}
            </Button>
          </div>
        </div>
      </div>
    </div>
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
