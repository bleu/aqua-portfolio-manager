"use client";

import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { base } from "wagmi/chains";
import { CreateBasketsPage } from "@/components/pages/CreateBasketsPage";
import { initialBaskets } from "@/lib/mockBaskets";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  const router = useRouter();
  const address = useVerifiedSafeAddress();
  const { tokens, isLoading } = useSafeBalances(address);
  // Base is the only chain wagmi.ts configures -- wagmi still reports whatever chain the wallet
  // actually sits on, so this is a real check, not a redundant one.
  const { chain } = useAccount();

  if (!address) {
    return <div className="min-h-screen" />;
  }

  return (
    <CreateBasketsPage
      network={chain?.name ?? "Base"}
      safeAddress={address}
      baskets={initialBaskets}
      safeTokens={tokens}
      tokensLoading={isLoading}
      isUnsupportedNetwork={chain !== undefined && chain.id !== base.id}
      onContinue={() => router.push("/setup/targets")}
    />
  );
}
