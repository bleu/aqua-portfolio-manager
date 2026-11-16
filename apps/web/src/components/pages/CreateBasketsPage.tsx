"use client";

import { useEffect, useMemo, useState } from "react";
import { AddBasketButton } from "@/components/AddBasketButton";
import { Banner } from "@/components/Banner";
import { BasketPanelHeader } from "@/components/BasketPanelHeader";
import { Footer } from "@/components/Footer";
import { SearchInput } from "@/components/SearchInput";
import { TokenIcon } from "@/components/TokenIcon";
import { TokenListRow } from "@/components/TokenListRow";
import { WelcomeModal } from "@/components/WelcomeModal";
import { WizardFooter } from "@/components/WizardFooter";
import { WizardLayout } from "@/components/WizardLayout";
import { BASKET_COLORS, getBasketColor } from "@/lib/basketColors";
import { loadDraftBaskets, saveDraftBaskets } from "@/lib/basketDraftsStorage";
import { cn } from "@/lib/cn";
import type { BasketDraft, SafeToken } from "@/lib/mockBaskets";
import { buildNavTabs } from "@/lib/navTabs";
import { dismissSafeBanner, hasDismissedSafeBanner } from "@/lib/safeWalletBannerStorage";
import { hasSeenWelcome, markWelcomeSeen } from "@/lib/welcomeModalStorage";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS = buildNavTabs("portfolio-manager");

/** Mirrors PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP/MAX_GROUPS -- a strategy that exceeds
 *  either can't ship on-chain, so the wizard blocks it here instead of failing silently later. */
const MAX_TOKENS_PER_BASKET = 5;
const MAX_BASKETS = 4;

export type CreateBasketsPageProps = {
  network: string;
  safeAddress: string;
  baskets: BasketDraft[];
  safeTokens: SafeToken[];
  tokensLoading?: boolean;
  /** True when the connected wallet is on a chain other than Base -- dims and disables the whole
   *  wizard card below the banner, matching the design reference exactly (this app is Base-only,
   *  see lib/wagmi.ts). The page wrapper owns the actual chain check; this component only renders
   *  what it's told. */
  isUnsupportedNetwork?: boolean;
  onBack?: () => void;
  onContinue?: () => void;
};

/** BLEUDEV-411 — "04C · Create baskets, two-column token selector": step 1 of the 4-step setup wizard. */
export function CreateBasketsPage({
  network,
  safeAddress,
  baskets,
  safeTokens,
  tokensLoading,
  isUnsupportedNetwork,
  onBack,
  onContinue,
}: CreateBasketsPageProps) {
  const [draftBaskets, setDraftBaskets] = useState(baskets);
  const [selectedBasketId, setSelectedBasketId] = useState(baskets[0]?.id);
  const [query, setQuery] = useState("");
  // Defaults to false so the first render always matches the server (no localStorage there),
  // same hydration-mismatch avoidance as the draftBaskets effect below.
  const [showWelcome, setShowWelcome] = useState(false);
  const [showSafeBanner, setShowSafeBanner] = useState(false);

  // Applied after mount, not as useState's initializer, so the first render always matches the
  // server-rendered baskets prop -- avoids a hydration mismatch between what the server sent and
  // whatever this browser's localStorage happens to hold.
  useEffect(() => {
    const stored = loadDraftBaskets(safeAddress);
    if (stored) {
      setDraftBaskets(stored);
      setSelectedBasketId(stored[0]?.id);
    }
  }, [safeAddress]);

  useEffect(() => {
    if (!hasSeenWelcome(safeAddress)) setShowWelcome(true);
  }, [safeAddress]);

  function dismissWelcome() {
    markWelcomeSeen(safeAddress);
    setShowWelcome(false);
  }

  useEffect(() => {
    if (!hasDismissedSafeBanner(safeAddress)) setShowSafeBanner(true);
  }, [safeAddress]);

  function dismissSafeWalletBanner() {
    dismissSafeBanner(safeAddress);
    setShowSafeBanner(false);
  }

  useEffect(() => {
    saveDraftBaskets(safeAddress, draftBaskets);
  }, [safeAddress, draftBaskets]);

  const selectedBasket = draftBaskets.find((basket) => basket.id === selectedBasketId) ?? draftBaskets[0];
  const assignedAddresses = new Set(draftBaskets.flatMap((basket) => basket.tokenAddresses));

  // A token the Safe holds none of can never satisfy attestBuildParameters' balance-within-
  // tolerance check (PortfolioManagerStrategyValidator.sol) -- it's always maximally unbalanced
  // against any nonzero target, so shipping with one in a basket is guaranteed to revert. Hiding
  // it from the picker entirely (not just discouraging it) stops that dead end before it starts.
  // Scoped to these two derivations only: tokens already added to a basket still need to render
  // via plain `safeTokens` lookups elsewhere in this file even if their balance later drops to 0.
  const fundedTokens = useMemo(() => safeTokens.filter((token) => token.balance > 0), [safeTokens]);

  // Tokens already in the selected basket sort first -- the design shows them at the top of this
  // same list (with a teal ✕ to remove), not in a separate "Tokens in this basket" chip row.
  const visibleTokens = useMemo(() => {
    const addedAddresses = new Set(selectedBasket?.tokenAddresses ?? []);
    return fundedTokens
      .filter((token) => {
        const q = query.trim().toLowerCase();
        return q === "" || token.symbol.toLowerCase().includes(q) || token.address.toLowerCase().includes(q);
      })
      .sort((a, b) => {
        const addedDiff = Number(addedAddresses.has(b.address)) - Number(addedAddresses.has(a.address));
        return addedDiff !== 0 ? addedDiff : b.value - a.value;
      });
  }, [fundedTokens, selectedBasket, query]);

  function toggleTokenInSelectedBasket(address: string) {
    if (!selectedBasket) return;
    const alreadyIn = selectedBasket.tokenAddresses.includes(address);
    if (!alreadyIn && selectedBasket.tokenAddresses.length >= MAX_TOKENS_PER_BASKET) return;
    setDraftBaskets((prev) =>
      prev.map((basket) =>
        basket.id !== selectedBasket.id
          ? basket
          : {
              ...basket,
              tokenAddresses: alreadyIn
                ? basket.tokenAddresses.filter((a) => a !== address)
                : [...basket.tokenAddresses, address],
            },
      ),
    );
  }

  function renameBasket(id: string, name: string) {
    setDraftBaskets((prev) => prev.map((basket) => (basket.id === id ? { ...basket, name } : basket)));
  }

  function removeTokenFromBasket(basketId: string, address: string) {
    setDraftBaskets((prev) =>
      prev.map((basket) =>
        basket.id !== basketId ? basket : { ...basket, tokenAddresses: basket.tokenAddresses.filter((a) => a !== address) },
      ),
    );
  }

  function addBasket() {
    if (draftBaskets.length >= MAX_BASKETS) return;
    const id = `basket-${draftBaskets.length + 1}`;
    const color = getBasketColor(draftBaskets.length).solid;
    setDraftBaskets((prev) => [...prev, { id, name: `Basket ${prev.length + 1}`, color, tokenAddresses: [] }]);
    setSelectedBasketId(id);
  }

  function deleteBasket(id: string) {
    const remaining = draftBaskets.filter((basket) => basket.id !== id);
    setDraftBaskets(remaining);
    if (selectedBasketId === id) setSelectedBasketId(remaining[0]?.id);
  }

  /** The gradient a basket's own chips use (Step1_Baskets_Filled.dc.html's .t-teal/.t-sal) is tied
   *  to its assigned flat color, not its position in the list -- looking it up by color keeps a
   *  basket's chip tint stable even if an earlier basket is deleted. */
  function chipGradientFor(basket: BasketDraft) {
    const index = BASKET_COLORS.indexOf(basket.color);
    return getBasketColor(index === -1 ? 0 : index);
  }

  const managedTokenCount = assignedAddresses.size;

  const banner = isUnsupportedNetwork ? (
    <Banner
      tone="warning"
      icon={
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c9ad78" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <circle cx="12" cy="12" r="9" />
          <path d="M12 8v5M12 16v.5" />
        </svg>
      }
      title="Unsupported network"
      description="Trim is only available on Base. Switch your network to Base to continue"
      action={
        <span className="flex items-center gap-2 text-sm font-semibold text-accent">
          Switch to Base in Safe
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M8 16L17 7M9 7h8v8" />
          </svg>
        </span>
      }
    />
  ) : (
    showSafeBanner && (
      <Banner
        tone="info"
        icon={
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#1b3a40" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M9 18h6M10 21h4M12 3a6 6 0 00-3.5 10.9c.6.5 1 1.2 1 2.1h5c0-.9.4-1.6 1-2.1A6 6 0 0012 3z" />
          </svg>
        }
        title="You're using a Safe Wallet"
        description="To improve your experience while activating your Portfolio Manager, we recommend using the Trim Safe App directly."
        action={
          <button type="button" onClick={dismissSafeWalletBanner} className="flex h-12 items-center gap-2 rounded-full border border-[#0e2226] px-6 text-sm font-semibold">
            Open Safe App
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M8 16L17 7M9 7h8v8" />
            </svg>
          </button>
        }
        className="mb-7"
      />
    )
  );

  return (
    <WizardLayout
      network={network}
      safeAddress={safeAddress}
      tabs={TABS}
      steps={WIZARD_STEPS}
      activeStepIndex={0}
      contentWidthPx={1200}
      modal={showWelcome ? <WelcomeModal onContinue={dismissWelcome} /> : undefined}
      banner={banner}
      dimmed={isUnsupportedNetwork}
      footer={<Footer />}
    >
        <div className="grid grid-cols-2 gap-6">
          <div className="flex flex-col gap-4 rounded-[28px] border border-white/[0.03] bg-[#16181b] p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h1 className="text-[26px] font-semibold text-white">Create your baskets</h1>
                <p className="mt-2 text-[15px] text-gray-400">Add baskets and choose their token composition.</p>
              </div>
              <span className="flex h-10 shrink-0 items-center rounded-full bg-[#212428] px-[18px] text-[17px] text-[#b5b9bd]">
                {draftBaskets.length} / {MAX_BASKETS}
              </span>
            </div>
            <div className="h-px bg-[#262a2f]" />

            {draftBaskets.map((basket) => {
              const tokens = safeTokens.filter((t) => basket.tokenAddresses.includes(t.address));
              const value = tokens.reduce((sum, t) => sum + t.value, 0);
              const selected = basket.id === selectedBasketId;
              const gradient = chipGradientFor(basket);
              const atTokenLimit = tokens.length >= MAX_TOKENS_PER_BASKET;
              return (
                <div
                  key={basket.id}
                  onClick={() => setSelectedBasketId(basket.id)}
                  className={cn(
                    "cursor-pointer rounded-[28px] border-[1.5px] px-6 py-[22px] transition-colors",
                    selected ? "border-accent bg-[#171a1d]" : "border-transparent bg-[#1a1d21] hover:border-white/10",
                  )}
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="text-xl font-semibold text-white">{basket.name}</p>
                      <p className="mt-1.5 text-sm text-[#8b9096]">
                        {tokens.length}/{MAX_TOKENS_PER_BASKET} tokens · ${value.toLocaleString()} managed
                      </p>
                    </div>
                    <button
                      type="button"
                      aria-label={`Delete ${basket.name}`}
                      onClick={(e) => {
                        e.stopPropagation();
                        deleteBasket(basket.id);
                      }}
                      className="flex size-11 shrink-0 items-center justify-center rounded-full bg-[#202429] text-[#cfd3d6] transition-colors hover:bg-[#262b31]"
                    >
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                        <path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3" />
                      </svg>
                    </button>
                  </div>

                  <div className="mt-3.5 flex flex-wrap items-center gap-2.5">
                    {tokens.map((token) => (
                      <span
                        key={token.address}
                        className="inline-flex h-[46px] items-center gap-2 rounded-full py-0 pr-3.5 pl-1.5 text-sm font-semibold text-[#0b0d10]"
                        style={{ background: `linear-gradient(180deg, ${gradient.chipFrom}, ${gradient.chipTo})` }}
                      >
                        <TokenIcon symbol={token.symbol} iconUrl={token.iconUrl} size={34} />
                        {token.symbol}
                        <button
                          type="button"
                          aria-label={`Remove ${token.symbol}`}
                          onClick={(e) => {
                            e.stopPropagation();
                            removeTokenFromBasket(basket.id, token.address);
                          }}
                        >
                          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                            <path d="M6 6l12 12M18 6L6 18" />
                          </svg>
                        </button>
                      </span>
                    ))}
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        setSelectedBasketId(basket.id);
                      }}
                      disabled={atTokenLimit}
                      className="flex h-[46px] items-center gap-2 rounded-full border border-border px-[18px] text-[15px] text-[#9aa0a5] transition-colors hover:border-accent/60 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                        <path d="M12 5v14M5 12h14" />
                      </svg>
                      Add token
                    </button>
                  </div>
                </div>
              );
            })}

            <AddBasketButton onClick={addBasket} disabled={draftBaskets.length >= MAX_BASKETS} />
            {draftBaskets.length >= MAX_BASKETS && (
              <div>
                <p className="text-sm text-red-500">Maximum baskets reached</p>
                <p className="mt-1.5 text-sm text-gray-500">
                  You can create up to {MAX_BASKETS} baskets. Remove a basket to add another.
                </p>
              </div>
            )}
          </div>

          {selectedBasket && (
            <div className="space-y-4 rounded-[28px] border border-white/[0.03] bg-[#16181b] p-6">
              <BasketPanelHeader name={selectedBasket.name} onRename={(name) => renameBasket(selectedBasket.id, name)} />

              <div className="flex items-center justify-between gap-4">
                <div>
                  <p className="text-lg font-semibold text-white">Add tokens</p>
                  <p className="mt-1 text-sm text-[#8b9096]">Choose from your wallet.</p>
                </div>
                <SearchInput
                  className="w-[260px]"
                  placeholder="Search tokens"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
              </div>

              {selectedBasket.tokenAddresses.length >= MAX_TOKENS_PER_BASKET && (
                <div>
                  <p className="text-sm text-red-500">
                    {MAX_TOKENS_PER_BASKET}/{MAX_TOKENS_PER_BASKET} Tokens added
                  </p>
                  <p className="mt-1.5 text-sm text-gray-500">
                    This basket has reached its token limit. Remove a token to add another.
                  </p>
                </div>
              )}

              <div className="max-h-64 space-y-1 overflow-y-auto">
                {tokensLoading && <p className="text-xs text-gray-500">Loading Safe balances…</p>}
                {!tokensLoading && query.trim() !== "" && visibleTokens.length === 0 && (
                  <p className="mb-2 text-sm text-gray-500">
                    No token found for &quot;{query}&quot;. Try a different search or select a token from the list below.
                  </p>
                )}
                {/* A no-results query falls back to the full, unfiltered list -- the design
                    reference shows it below the message rather than leaving the list empty. */}
                {!tokensLoading &&
                  (visibleTokens.length > 0 ? visibleTokens : fundedTokens).map((token) => (
                    <TokenListRow
                      key={token.address}
                      token={token}
                      balance={token.balance}
                      value={token.value}
                      added={selectedBasket.tokenAddresses.includes(token.address)}
                      disabled={selectedBasket.tokenAddresses.length >= MAX_TOKENS_PER_BASKET}
                      onToggle={() => toggleTokenInSelectedBasket(token.address)}
                    />
                  ))}
              </div>
            </div>
          )}
        </div>

        <div className="mt-6">
          <WizardFooter
            continueLabel="Continue"
            showBack
            onBack={onBack}
            onContinue={onContinue}
            continueDisabled={managedTokenCount === 0 || isUnsupportedNetwork}
          />
        </div>
    </WizardLayout>
  );
}
