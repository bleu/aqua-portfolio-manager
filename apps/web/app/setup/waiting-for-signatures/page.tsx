"use client";

import { useAccount } from "wagmi";
import { WaitingForSafeSignaturesPage } from "@/components/pages/WaitingForSafeSignaturesPage";
import { loadDraftParameters } from "@/lib/parametersDraftStorage";
import { useSafeThreshold } from "@/lib/useSafeThreshold";

export default function Page() {
  const { address } = useAccount();
  const { threshold } = useSafeThreshold(address);

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
      transactionHash="0x0000000000000000000000000000000000000000000000000000000000000000"
      submittedAt="Just now"
      priceDeviationPct={draftParameters?.priceDeviationPct ?? 0}
    />
  );
}
