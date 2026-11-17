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
  // No `?? safeConnector` fallback here: the safe connector can only ever succeed embedded inside
  // Safe{Wallet}'s own iframe (see the auto-connect effect below) -- a manual click from a plain
  // browser tab against it was guaranteed to throw the Safe Apps SDK's own "Provider not found"
  // straight from @wagmi/core, with no iframe bridge for it to find. That's what was happening
  // locally without NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID set, not a connector malfunction.
  const manualConnector = walletConnectConnector;
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
  //
  // Gated on actually being in an iframe: the assumption that this attempt "always fails" outside
  // Safe{Wallet} turned out to be wrong whenever a browser extension wallet (e.g. Rabby) is
  // installed -- observed directly, the safe connector's handshake probe falls through to that
  // injected provider instead of rejecting, silently connecting the user's EOA on whatever chain
  // it happens to be on and sending them into a dashboard built for a verified Safe on Base. A
  // real Safe App is always loaded inside Safe{Wallet}'s own iframe, so skipping the attempt
  // outside of one costs nothing for the real use case and closes this off entirely.
  const attemptedAutoConnect = useRef(false);
  useEffect(() => {
    const isEmbedded = window.self !== window.top;
    if (attemptedAutoConnect.current || !safeConnector || !isEmbedded) return;
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
      onConnectSafe={async () => {
        setShowConnectError(true);
        if (!manualConnector) return;
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
      }}
      isConnecting={isPending}
      connectError={
        showConnectError
          ? (manualConnector
              ? error?.message
              : "WalletConnect isn't configured in this environment (set NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID -- see https://cloud.reown.com). Open this page inside Safe{Wallet} instead to connect.")
          : undefined
      }
    />
  );
}
