"use client";

import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { CreateBasketsPage } from "@/components/pages/CreateBasketsPage";
import { initialBaskets } from "@/lib/mockBaskets";
import { useSafeBalances } from "@/lib/useSafeBalances";

export default function Page() {
  const router = useRouter();
  const { address } = useAccount();
  const { tokens, isLoading } = useSafeBalances(address);

  if (!address) {
    return <div className="min-h-screen" />;
  }

  return (
    <CreateBasketsPage
      network="Base"
      safeAddress={address}
      baskets={initialBaskets}
      safeTokens={tokens}
      tokensLoading={isLoading}
      onContinue={() => router.push("/setup/targets")}
    />
  );
}
