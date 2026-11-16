"use client";

import { useRouter } from "next/navigation";
import { SetTargetAllocationPage } from "@/components/pages/SetTargetAllocationPage";
import { loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { loadBalancesSnapshot } from "@/lib/safeBalancesSnapshot";
import { saveDraftTargets } from "@/lib/targetsDraftStorage";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  const router = useRouter();
  const address = useVerifiedSafeAddress();
  // Reads step 1's balance snapshot, not a fresh live fetch -- keeps a basket's managed value
  // stable across the wizard (see lib/safeBalancesSnapshot.ts). `useSafeBalances` itself is still
  // called as the bootstrap fallback for a direct/deep-linked visit that skipped step 1.
  const { tokens: liveTokens } = useSafeBalances(address);

  if (!address) {
    return <div className="min-h-screen" />;
  }

  const tokens = loadBalancesSnapshot(address) ?? liveTokens;
  const draftBaskets = loadDraftBaskets(address) ?? initialBaskets;
  const baskets = draftBaskets.map((basket) => {
    const basketTokens = tokens.filter((t) => basket.tokenAddresses.includes(t.address));
    return {
      id: basket.id,
      name: basket.name,
      color: basket.color,
      tokenSymbols: basketTokens.map((t) => t.symbol),
      currentValue: basketTokens.reduce((sum, t) => sum + t.value, 0),
    };
  });

  return (
    <SetTargetAllocationPage
      network="Base"
      safeAddress={address}
      baskets={baskets}
      onBack={() => router.push("/setup/baskets")}
      onContinue={(targetsPct) => {
        saveDraftTargets(address, targetsPct);
        router.push("/setup/parameters");
      }}
    />
  );
}
