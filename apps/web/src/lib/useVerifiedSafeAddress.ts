"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Address } from "viem";
import { useAccount, useDisconnect } from "wagmi";

/** wagmi's own `isConnected`/`address` reflect locally cached session state, not whether the
 *  connection is still actually alive -- if the wallet disconnects on its own side (e.g. a
 *  Safe{Wallet} session ended there), wagmi keeps reporting "connected" indefinitely, since
 *  nothing automatically tells it otherwise. Observed directly: disconnecting from inside
 *  Safe{Wallet}, then even reloading this app, still showed it as connected -- every request sent
 *  into that session afterward just went nowhere, with no error.
 *
 *  This verifies the connection with a real, lightweight eth_accounts request before trusting it;
 *  if that fails or comes back empty, it disconnects locally and sends the user back to the
 *  connect page, instead of leaving them stuck on a page that looks connected but can't actually
 *  do anything.
 *
 *  @returns `address` -- only set once live-verified; undefined while checking, while there's no
 *           connection at all, or once a dead connection has been caught and is being redirected.
 *           Every page that needs a connected Safe should use this instead of useAccount()'s own
 *           `address` directly. */
const VERIFY_TIMEOUT_MS = 8_000;

/** A dead WalletConnect relay can leave `eth_accounts` -- or `connector.getProvider()` itself --
 *  pending forever instead of rejecting, so the caller is stuck on an unverified connection with
 *  no error and no redirect. Racing the WHOLE check against a timeout (not just the request call)
 *  guarantees the existing catch path (disconnect + send back to "/") still runs within
 *  VERIFY_TIMEOUT_MS no matter which step hangs -- wrapping only the inner request left
 *  `getProvider()` itself unguarded, which is exactly the hang observed in production: approving
 *  a WalletConnect session, landing on /dashboard, and sitting on a blank screen indefinitely. */
function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Timed out verifying the wallet connection")), ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

export function useVerifiedSafeAddress(): Address | undefined {
  const router = useRouter();
  const { address: cachedAddress, isConnected, connector } = useAccount();
  const { disconnect } = useDisconnect();
  const [verifiedAddress, setVerifiedAddress] = useState<Address>();
  const checkedFor = useRef<string | undefined>(undefined);

  useEffect(() => {
    if (!isConnected || !connector || !cachedAddress) {
      setVerifiedAddress(undefined);
      return;
    }
    // Re-verifies once per distinct cached address, not on every render -- once confirmed live
    // for this session, later renders just trust it (same baseline every other page already
    // assumed, just gated behind one real check instead of none).
    if (checkedFor.current === cachedAddress) return;
    checkedFor.current = cachedAddress;

    // Narrowed to a local const so the nested async function below doesn't need TypeScript to
    // re-prove `connector` is still defined by the time it actually runs.
    const liveConnector = connector;
    async function verify(): Promise<string[] | undefined> {
      const provider = (await liveConnector.getProvider()) as {
        request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
      };
      return (await provider.request({ method: "eth_accounts" })) as string[] | undefined;
    }

    let cancelled = false;
    (async () => {
      try {
        const accounts = await withTimeout(verify(), VERIFY_TIMEOUT_MS);
        if (cancelled) return;
        if (accounts?.some((a) => a.toLowerCase() === cachedAddress.toLowerCase())) {
          setVerifiedAddress(cachedAddress);
        } else {
          disconnect();
          router.push("/");
        }
      } catch {
        if (cancelled) return;
        disconnect();
        router.push("/");
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [isConnected, connector, cachedAddress, disconnect, router]);

  return verifiedAddress;
}
