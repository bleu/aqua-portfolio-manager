"use client";

import { useRouter } from "next/navigation";
import { EmptyDashboardPage } from "@/components/pages/EmptyDashboardPage";

export default function Page() {
  const router = useRouter();
  return (
    <EmptyDashboardPage
      network="Ethereum"
      safeAddress="0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B"
      onStartSetup={() => router.push("/setup/baskets")}
    />
  );
}
