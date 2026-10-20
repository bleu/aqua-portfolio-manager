"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { WaitingForSafeSignaturesPage } from "@/components/pages/WaitingForSafeSignaturesPage";
import { loadDraftParameters } from "@/lib/parametersDraftStorage";
import { useSafeThreshold } from "@/lib/useSafeThreshold";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

/** Safe{Wallet}'s own URL scheme: a chain-prefixed Safe identifier (`base:0x...`) and, for a
 *  specific transaction, an id of the form `multisig_<safeAddress>_<safeTxHash>`. */
function safeWalletQueueUrl(safeAddress: string): string {
  return `https://app.safe.global/transactions/queue?safe=base:${safeAddress}`;
}
function safeWalletTransactionUrl(safeAddress: string, safeTxHash: string): string {
  return `https://app.safe.global/transactions/tx?safe=base:${safeAddress}&id=multisig_${safeAddress}_${safeTxHash}`;
}

export default function Page() {
  return (
    <Suspense fallback={<div className="min-h-screen" />}>
      <WaitingForSignaturesPageContent />
    </Suspense>
  );
}

/** useSearchParams() (for the proposed tx's safeTxHash) forces this subtree into a Suspense
 *  boundary during static prerendering -- split out so Page itself can provide the fallback. */
function WaitingForSignaturesPageContent() {
  const address = useVerifiedSafeAddress();
  const { threshold } = useSafeThreshold(address);
  const searchParams = useSearchParams();
  const safeTxHash = searchParams.get("tx") ?? "";

  if (!address) {
    return <div className="min-h-screen" />;
  }

  const draftParameters = loadDraftParameters(address);

  return (
    <WaitingForSafeSignaturesPage
      network="Base"
      safeAddress={address}
      signaturesRequired={threshold ?? 1}
      // The proposer's own signature is collected the moment the transaction is proposed --
      // real-time updates past this point need the Safe Transaction Service, out of scope here.
      signaturesCollected={1}
      transactionHash={safeTxHash}
      submittedAt="Just now"
      priceDeviationPct={draftParameters?.priceDeviationPct ?? 0}
      onOpenInSafe={() => window.open(safeWalletQueueUrl(address), "_blank", "noopener,noreferrer")}
      onViewTransaction={() =>
        window.open(safeWalletTransactionUrl(address, safeTxHash), "_blank", "noopener,noreferrer")
      }
    />
  );
}
