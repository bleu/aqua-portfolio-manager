"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { ReviewPortfolioManagerPage } from "@/components/pages/ReviewPortfolioManagerPage";
import { loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { loadDraftParameters } from "@/lib/parametersDraftStorage";
import { proposeShipStrategyTransaction } from "@/lib/safeProposal";
import { loadDraftTargets } from "@/lib/targetsDraftStorage";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useSafeThreshold } from "@/lib/useSafeThreshold";

/** Mobile wallets round-trip a signature request through a push notification, which can take a
 *  while -- generous, but still bounded, so "Create transaction" can never freeze forever if the
 *  wallet never responds at all (observed: the button stuck on "Creating transaction..." with no
 *  error, which is a hung promise, not a thrown one -- this guarantees it eventually resolves). */
const CREATE_TRANSACTION_TIMEOUT_MS = 90_000;
const CREATE_TRANSACTION_TIMEOUT_MESSAGE = "__aqua_pm_create_transaction_timeout__";

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(CREATE_TRANSACTION_TIMEOUT_MESSAGE)), timeoutMs);
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

export default function Page() {
  const router = useRouter();
  const { address, connector } = useAccount();
  const { tokens, rawBalances } = useSafeBalances(address);
  const { threshold } = useSafeThreshold(address);
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string>();

  if (!address) {
    return <div className="min-h-screen" />;
  }

  const draftBaskets = loadDraftBaskets(address) ?? initialBaskets;
  const draftTargets = loadDraftTargets(address) ?? {};
  const draftParameters = loadDraftParameters(address);

  const total = draftBaskets.reduce((sum, basket) => {
    const basketTokens = tokens.filter((t) => basket.tokenAddresses.includes(t.address));
    return sum + basketTokens.reduce((s, t) => s + t.value, 0);
  }, 0);

  const baskets = draftBaskets.map((basket) => {
    const basketTokens = tokens.filter((t) => basket.tokenAddresses.includes(t.address));
    const currentValue = basketTokens.reduce((sum, t) => sum + t.value, 0);
    return {
      id: basket.id,
      name: basket.name,
      color: basket.color,
      tokenSymbols: basketTokens.map((t) => t.symbol),
      currentValue,
      currentPct: total > 0 ? (currentValue / total) * 100 : 0,
      targetPct: draftTargets[basket.id] ?? (total > 0 ? (currentValue / total) * 100 : 0),
    };
  });

  const priceDeviationPct = draftParameters?.priceDeviationPct ?? 0;
  const lpFeePct = draftParameters?.lpFeePct ?? 0;

  /** Maps a raw thrown error to a plain-language message a non-technical user can act on --
   *  the raw error (a viem/Safe-SDK message, a stack trace) always goes to the console for
   *  debugging, but never directly onto the screen. Unrecognized errors fall back to one generic
   *  message rather than leaking library internals. */
  function describeCreateTransactionError(err: unknown): string {
    console.error("Failed to create the Safe transaction:", err);
    const message = err instanceof Error ? err.message : String(err);

    if (/user rejected|user denied|denied the request/i.test(message)) {
      return "You declined the signature request in your wallet. Nothing was created -- try again when you're ready.";
    }
    if (/NEXT_PUBLIC_SAFE_API_KEY/.test(message)) {
      return "This app isn't fully configured to propose Safe transactions yet. Contact the team.";
    }
    if (/registered Base-mainnet token\/feed universe/.test(message)) {
      return "One of the tokens in your baskets isn't supported yet. Go back and remove it, or pick a different token.";
    }
    if (/Target allocations must sum/.test(message)) {
      return "Your target allocations need to add up to more than 0%. Go back to Targets and set them.";
    }
    if (/multi-owner Safe isn't supported/.test(message)) {
      return "This Safe has more than one owner, which isn't supported by this flow yet. Contact the team.";
    }
    if (message === CREATE_TRANSACTION_TIMEOUT_MESSAGE) {
      return "This is taking too long -- check your wallet for a pending signature request. If there isn't one, try again.";
    }
    return "Something went wrong creating this transaction. Try again, or contact the team if this keeps happening.";
  }

  async function handleCreateTransaction() {
    if (!connector) return;
    setCreateError(undefined);
    setIsCreating(true);
    try {
      const provider = await connector.getProvider();
      const { safeTxHash } = await withTimeout(
        proposeShipStrategyTransaction({
          safeAddress: address as `0x${string}`,
          provider: provider as {
            request: (args: { method: string; params?: unknown[] | object }) => Promise<unknown>;
          },
          groups: draftBaskets.map((basket) => ({
            name: basket.name,
            targetPct: draftTargets[basket.id] ?? 0,
            tokenAddresses: basket.tokenAddresses as `0x${string}`[],
          })),
          feeBpsPm: BigInt(Math.round(lpFeePct * 1e7)),
          maxDeviationBpsPm: BigInt(Math.round(priceDeviationPct * 1e7)),
          balances: rawBalances as Record<`0x${string}`, bigint>,
        }),
        CREATE_TRANSACTION_TIMEOUT_MS,
      );
      router.push(`/setup/waiting-for-signatures?tx=${safeTxHash}`);
    } catch (err) {
      setCreateError(describeCreateTransactionError(err));
    } finally {
      setIsCreating(false);
    }
  }

  return (
    <ReviewPortfolioManagerPage
      network="Base"
      safeAddress={address}
      baskets={baskets}
      priceDeviationPct={priceDeviationPct}
      lpFeePct={lpFeePct}
      signaturesRequired={threshold ?? 1}
      onBack={() => router.push("/setup/parameters")}
      onCreateTransaction={handleCreateTransaction}
      isCreatingTransaction={isCreating}
      createTransactionError={createError}
    />
  );
}
