"use client";

import { Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { WaitingForSafeSignaturesPage } from "@/components/pages/WaitingForSafeSignaturesPage";
import { loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { loadDraftParameters } from "@/lib/parametersDraftStorage";
import { loadBalancesSnapshot } from "@/lib/safeBalancesSnapshot";
import { loadDraftTargets } from "@/lib/targetsDraftStorage";
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
  const router = useRouter();
  const address = useVerifiedSafeAddress();
  const { threshold } = useSafeThreshold(address);
  const searchParams = useSearchParams();
  const safeTxHash = searchParams.get("tx") ?? "";

  if (!address) {
    return <div className="min-h-screen" />;
  }

  const draftParameters = loadDraftParameters(address);
  const draftBaskets = loadDraftBaskets(address) ?? initialBaskets;
  const draftTargets = loadDraftTargets(address) ?? {};
  // Same wizard-wide snapshot Targets/Review read -- keeps this screen's figures matching what
  // the user saw throughout, not a fresh live fetch.
  const snapshotTokens = loadBalancesSnapshot(address) ?? [];

  const baskets = draftBaskets.map((basket) => {
    const basketTokens = snapshotTokens.filter((t) => basket.tokenAddresses.includes(t.address));
    const currentValue = basketTokens.reduce((sum, t) => sum + t.value, 0);
    const total = snapshotTokens.reduce((sum, t) => sum + t.value, 0);
    return {
      id: basket.id,
      name: basket.name,
      tokenSymbols: basketTokens.map((t) => t.symbol),
      currentValue,
      currentPct: total > 0 ? (currentValue / total) * 100 : 0,
      targetPct: draftTargets[basket.id] ?? 0,
    };
  });

  return (
    <WaitingForSafeSignaturesPage
      network="Base"
      safeAddress={address}
      signaturesRequired={threshold ?? 1}
      // The proposer's own signature is collected the moment the transaction is proposed --
      // real-time updates past this point need the Safe Transaction Service, out of scope here.
      signaturesCollected={1}
      transactionHash={safeTxHash}
      priceDeviationPct={draftParameters?.priceDeviationPct ?? 0}
      lpFeePct={draftParameters?.lpFeePct ?? 0}
      baskets={baskets}
      onOpenInSafe={() => window.open(safeWalletQueueUrl(address), "_blank", "noopener,noreferrer")}
      onViewTransaction={() =>
        window.open(safeWalletTransactionUrl(address, safeTxHash), "_blank", "noopener,noreferrer")
      }
      onSelectTab={(label) => {
        if (label === "Activity") router.push("/dashboard/history");
        if (label === "Home") router.push("/dashboard");
      }}
    />
  );
}
