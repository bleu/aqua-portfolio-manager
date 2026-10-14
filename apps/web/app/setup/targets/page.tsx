"use client";

import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { SetTargetAllocationPage } from "@/components/pages/SetTargetAllocationPage";
import { loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { useSafeBalances } from "@/lib/useSafeBalances";

export default function Page() {
  const router = useRouter();
  const { address } = useAccount();
  const { tokens } = useSafeBalances(address);

  if (!address) {
    return <div className="min-h-screen" />;
  }

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
      onContinue={() => router.push("/setup/parameters")}
    />
  );
}
