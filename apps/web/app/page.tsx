"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { ConnectSafePage } from "@/components/pages/ConnectSafePage";
import { wagmiConfig } from "@/lib/wagmi";

const safeConnector = wagmiConfig.connectors.find((c) => c.type === "safe");
const walletConnectConnector = wagmiConfig.connectors.find((c) => c.type === "walletConnect");

/** Connection is Safe-only (ADR-0011), not a generic wallet -- see wagmi.ts's own doc comment. */
export default function Page() {
  const router = useRouter();
  const { isConnected } = useAccount();
  const { connect, isPending, error } = useConnect();
  const { disconnectAsync } = useDisconnect();
  const manualConnector = walletConnectConnector ?? safeConnector;
  // Suppresses the silent auto-connect attempt's own failure from showing as a user-facing
  // error -- outside of actually being embedded in Safe{Wallet}, that attempt always fails, and
  // it isn't something the user did. Only a failure from onConnectSafe's own click below should
  // ever surface here.
  const [showConnectError, setShowConnectError] = useState(false);

  // Auto-attempts the Safe connector once on mount, for when this page is actually embedded
  // inside Safe{Wallet} as a Safe App. A real attempt (not a separate silent one) because
  // wagmi's connector-level pending/error state is shared across hook instances targeting the
  // same connector -- two independent useConnect() calls here fought over it instead of
  // isolating cleanly.
  const attemptedAutoConnect = useRef(false);
  useEffect(() => {
    if (attemptedAutoConnect.current || !safeConnector) return;
    attemptedAutoConnect.current = true;
    connect({ connector: safeConnector });
    // Only ever attempted once, on mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isConnected) router.push("/dashboard");
  }, [isConnected, router]);

  return (
    <ConnectSafePage
      onConnectSafe={
        manualConnector
          ? async () => {
              setShowConnectError(true);
              // A connector can be left internally marked "connected" after a session died on the
              // wallet's side (useVerifiedSafeAddress catches that and sends the user back here,
              // but doesn't -- and can't reliably -- fully reset the connector itself). Clicking
              // Connect then throws ConnectorAlreadyConnectedError before even attempting a new
              // connection. Forcing a disconnect first guarantees a clean slate either way --
              // disconnecting an already-disconnected connector is a harmless no-op.
              try {
                await disconnectAsync({ connector: manualConnector });
              } catch {
                // Nothing to tear down, or the old session was already dead -- fine, proceed.
              }
              connect({ connector: manualConnector });
            }
          : undefined
      }
      isConnecting={isPending}
      connectError={showConnectError ? error?.message : undefined}
    />
  );
}
