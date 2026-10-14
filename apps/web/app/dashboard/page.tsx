"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { useAccount } from "wagmi";
import { EmptyDashboardPage } from "@/components/pages/EmptyDashboardPage";

export default function Page() {
  const router = useRouter();
  const { address, chain, isConnected } = useAccount();

  // No Safe connected yet (e.g. this URL was opened directly) -- send back to the connect flow
  // instead of rendering a header for a wallet that isn't actually there.
  useEffect(() => {
    if (!isConnected) router.push("/");
  }, [isConnected, router]);

  if (!isConnected || !address) return null;

  return (
    <EmptyDashboardPage
      network={chain?.name ?? "Base"}
      safeAddress={address}
      onStartSetup={() => router.push("/setup/baskets")}
    />
  );
}
