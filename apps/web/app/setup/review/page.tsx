"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Address, Hex } from "viem";
import { useAccount } from "wagmi";
import { ReviewPortfolioManagerPage, type TransactionStep } from "@/components/pages/ReviewPortfolioManagerPage";
import { loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { loadDraftParameters } from "@/lib/parametersDraftStorage";
import {
  buildShipSteps,
  computeStrategyHash,
  isStepAlreadyDone,
  sendTransaction,
  sendTransactionsViaSafeAppsSdk,
  STEP_TIMEOUT_MESSAGE,
} from "@/lib/safeProposal";
import { loadDraftTargets } from "@/lib/targetsDraftStorage";
import { useBasketScopeConflict } from "@/lib/useBasketScopeConflict";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useSafeThreshold } from "@/lib/useSafeThreshold";
import { useStrategyAlreadyShipped } from "@/lib/useStrategyAlreadyShipped";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  const router = useRouter();
  const address = useVerifiedSafeAddress();
  const { connector } = useAccount();
  const { tokens, rawBalances } = useSafeBalances(address);
  const { threshold } = useSafeThreshold(address);
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string>();
  const [steps, setSteps] = useState<TransactionStep[]>();

  const draftBaskets = address ? loadDraftBaskets(address) ?? initialBaskets : initialBaskets;
  const draftTargets = address ? loadDraftTargets(address) ?? {} : {};
  const draftParameters = address ? loadDraftParameters(address) : undefined;
  const priceDeviationPct = draftParameters?.priceDeviationPct ?? 0;
  const lpFeePct = draftParameters?.lpFeePct ?? 0;

  const { conflicts: scopeConflicts, error: scopeConflictError } = useBasketScopeConflict(
    address as Address | undefined,
    draftBaskets.map((b) => ({ name: b.name, tokenAddresses: b.tokenAddresses as Address[] })),
  );
  const hasScopeConflict = !!scopeConflicts && scopeConflicts.length > 0;

  // Only meaningful once a real Safe address is connected -- computeStrategyHash doesn't need
  // tokens/balances, so it's safe to derive this before the early return below. Swallowed on
  // purpose: an incomplete draft (e.g. targets not set yet, same guard buildShipSteps itself
  // hits) just means the check can't run yet, not a page-breaking render error.
  let strategyHash: Hex | undefined;
  if (address) {
    try {
      strategyHash = computeStrategyHash(
        address as Address,
        draftBaskets.map((basket) => ({
          name: basket.name,
          targetPct: draftTargets[basket.id] ?? 0,
          tokenAddresses: basket.tokenAddresses as Address[],
        })),
        BigInt(Math.round(lpFeePct * 1e7)),
        BigInt(Math.round(priceDeviationPct * 1e7)),
      );
    } catch {
      strategyHash = undefined;
    }
  }
  const { alreadyShipped, error: alreadyShippedCheckError } = useStrategyAlreadyShipped(strategyHash);

  if (!address) {
    return <div className="min-h-screen" />;
  }

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

  /** Maps a raw thrown error to a plain-language message a non-technical user can act on --
   *  the raw error (a viem/wallet-provider message, a stack trace) always goes to the console for
   *  debugging, but never directly onto the screen. Unrecognized errors fall back to one generic
   *  message rather than leaking library internals. */
  function describeCreateTransactionError(err: unknown): string {
    console.error("Failed to create the Safe transaction:", err);
    const message = err instanceof Error ? err.message : String(err);

    if (/user rejected|user denied|denied the request/i.test(message)) {
      return "You declined a signature request in your wallet. Nothing was created -- try again when you're ready.";
    }
    if (/registered Base-mainnet token\/feed universe/.test(message)) {
      return "One of the tokens in your baskets isn't supported yet. Go back and remove it, or pick a different token.";
    }
    if (/Target allocations must sum/.test(message)) {
      return "Your target allocations need to add up to more than 0%. Go back to Targets and set them.";
    }
    if (message === STEP_TIMEOUT_MESSAGE) {
      return "This step is taking too long -- check your wallet for a pending signature request. If there isn't one, try again.";
    }
    return "Something went wrong creating this transaction. Try again, or contact the team if this keeps happening.";
  }

  async function handleCreateTransaction() {
    if (!connector) return;
    if (hasScopeConflict) return;
    if (alreadyShipped) return;
    if ((threshold ?? 1) > 1) {
      setCreateError("This Safe needs more than one signature, which isn't supported by this flow yet.");
      return;
    }
    setCreateError(undefined);
    setIsCreating(true);

    const tokenSymbols = Object.fromEntries(tokens.map((t) => [t.address, t.symbol])) as Record<Address, string>;
    const builtSteps = buildShipSteps({
      safeAddress: address as Address,
      groups: draftBaskets.map((basket) => ({
        name: basket.name,
        targetPct: draftTargets[basket.id] ?? 0,
        tokenAddresses: basket.tokenAddresses as Address[],
      })),
      feeBpsPm: BigInt(Math.round(lpFeePct * 1e7)),
      maxDeviationBpsPm: BigInt(Math.round(priceDeviationPct * 1e7)),
      balances: rawBalances as Record<Address, bigint>,
      tokenSymbols,
    });
    setSteps(builtSteps.map((step) => ({ label: step.label, status: "pending" })));

    try {
      // A retry after an earlier partial failure shouldn't ask the wallet to reconfirm a step
      // that already went through on a prior attempt -- check each on-chain first, mark those
      // done immediately, and only bundle what's actually left into the one transaction below.
      const remaining: { index: number; step: (typeof builtSteps)[number] }[] = [];
      for (let i = 0; i < builtSteps.length; i++) {
        const step = builtSteps[i]!;
        if (await isStepAlreadyDone(step, address as Address)) {
          setSteps((prev) => prev?.map((s, j) => (j === i ? { ...s, status: "done" } : s)));
        } else {
          remaining.push({ index: i, step });
        }
      }

      let txHash: Address | undefined;
      if (remaining.length > 0 && connector.id === "safe") {
        // Embedded as a Safe App: one real Safe batch via the Safe Apps SDK, which Safe{Wallet}
        // itself constructs (and correctly delegates into) -- see sendTransactionsViaSafeAppsSdk's
        // own doc comment for why this replaced packing calls into MultiSendCallOnly by hand.
        setSteps((prev) => prev?.map((s, j) => (remaining.some((r) => r.index === j) ? { ...s, status: "active" } : s)));
        try {
          txHash = await sendTransactionsViaSafeAppsSdk(remaining.map(({ step }) => ({ to: step.to, data: step.data })));
        } catch (stepErr) {
          setSteps((prev) => prev?.map((s, j) => (remaining.some((r) => r.index === j) ? { ...s, status: "error" } : s)));
          throw stepErr;
        }
        setSteps((prev) => prev?.map((s, j) => (remaining.some((r) => r.index === j) ? { ...s, status: "done" } : s)));
      } else if (remaining.length > 0) {
        // Any other connector (WalletConnect): plain eth_sendTransaction has no way to ask Safe to
        // batch, so each remaining step goes as its own top-level call, one signature each -- see
        // sendTransaction's own doc comment for why this is correct where batching wasn't.
        for (const { index, step } of remaining) {
          setSteps((prev) => prev?.map((s, j) => (j === index ? { ...s, status: "active" } : s)));
          const provider = (await connector.getProvider()) as {
            request: (args: { method: string; params?: unknown[] | object }) => Promise<unknown>;
          };
          try {
            txHash = await sendTransaction(step.to, step.data, address as Address, provider);
          } catch (stepErr) {
            setSteps((prev) => prev?.map((s, j) => (j === index ? { ...s, status: "error" } : s)));
            throw stepErr;
          }
          setSteps((prev) => prev?.map((s, j) => (j === index ? { ...s, status: "done" } : s)));
        }
      }

      router.push(`/setup/activated?tx=${txHash}`);
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
      transactionSteps={steps}
      scopeConflicts={scopeConflicts}
      scopeConflictCheckError={scopeConflictError}
      alreadyShipped={alreadyShipped}
      alreadyShippedCheckError={alreadyShippedCheckError}
    />
  );
}
