"use client";

import { AppHeader } from "@/components/AppHeader";
import { Button } from "@/components/Button";
import { DetailRow } from "@/components/DetailRow";
import { Disclosure } from "@/components/Disclosure";
import { SignatureProgressBar } from "@/components/SignatureProgressBar";
import { StatusIcon } from "@/components/StatusIcon";
import type { TabNavItem } from "@/components/TabNav";
import { truncateAddress } from "@/lib/format";

const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];

export type WaitingForSafeSignaturesPageProps = {
  network: string;
  safeAddress: string;
  signaturesRequired: number;
  signaturesCollected: number;
  transactionHash: string;
  submittedAt: string;
  priceDeviationPct: number;
  onOpenInSafe?: () => void;
  onViewTransaction?: () => void;
};

/** Reached after BLEUDEV-416's "Create transaction" proposes the Safe transaction -- outside the
 *  4-step wizard, so no WizardStepper here. */
export function WaitingForSafeSignaturesPage({
  network,
  safeAddress,
  signaturesRequired,
  signaturesCollected,
  transactionHash,
  submittedAt,
  priceDeviationPct,
  onOpenInSafe,
  onViewTransaction,
}: WaitingForSafeSignaturesPageProps) {
  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto mt-16 max-w-md px-6">
        <div className="rounded-xl border border-border bg-surface-card p-6">
          <div className="flex flex-col items-center text-center">
            <StatusIcon variant="pending" />
            <h1 className="mt-4 text-lg font-semibold text-white">Waiting for Safe signatures</h1>
            <p className="mt-1 text-sm text-gray-400">
              The Portfolio Manager remains inactive until the transaction is executed.
            </p>
          </div>

          <div className="mt-6 border-t border-border pt-4">
            <div className="flex items-center justify-between text-sm">
              <span className="text-gray-300">Signatures</span>
              <span className="font-medium text-white">
                {signaturesCollected} of {signaturesRequired}
              </span>
            </div>
            <SignatureProgressBar className="mt-2" total={signaturesRequired} signed={signaturesCollected} />
            <p className="mt-2 text-xs text-gray-500">The last signer executes the transaction.</p>
          </div>

          <div className="mt-6 border-t border-border pt-4">
            <p className="text-[11px] font-medium tracking-wide text-gray-500 uppercase">Transaction details</p>
            <div className="mt-2">
              <DetailRow label="Safe" value={truncateAddress(safeAddress)} />
              <DetailRow label="Network" value={network} />
              <DetailRow label="Transaction" value={truncateAddress(transactionHash)} />
              <DetailRow label="Submitted" value={submittedAt} />
              <DetailRow label="Price protection" value={`${priceDeviationPct}% at execution`} />
            </div>
            <div className="mt-3">
              <Disclosure label="View strategy configuration">
                The baskets, targets, and parameters configured in this strategy are encoded in the transaction
                above and can&apos;t be changed after it executes.
              </Disclosure>
            </div>
          </div>

          <Button variant="accent" className="mt-6 w-full" onClick={onOpenInSafe}>
            Open in Safe
          </Button>
          <button
            type="button"
            onClick={onViewTransaction}
            className="mt-3 w-full text-center text-sm text-gray-500 hover:text-gray-300"
          >
            View transaction
          </button>
        </div>
      </div>
    </div>
  );
}
