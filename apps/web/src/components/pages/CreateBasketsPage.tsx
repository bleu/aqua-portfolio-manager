"use client";

import { useEffect, useMemo, useState } from "react";
import { AddBasketButton } from "@/components/AddBasketButton";
import { AppHeader } from "@/components/AppHeader";
import { BasketPanelHeader } from "@/components/BasketPanelHeader";
import { GroupSummaryCard } from "@/components/GroupSummaryCard";
import { InfoBanner } from "@/components/InfoBanner";
import { SearchInput } from "@/components/SearchInput";
import type { TabNavItem } from "@/components/TabNav";
import { TokenChip } from "@/components/TokenChip";
import { TokenListRow } from "@/components/TokenListRow";
import { WizardFooter } from "@/components/WizardFooter";
import { WizardStepper } from "@/components/WizardStepper";
import { loadDraftBaskets, saveDraftBaskets } from "@/lib/basketDraftsStorage";
import type { BasketDraft, SafeToken } from "@/lib/mockBaskets";

const WIZARD_STEPS = [{ label: "Baskets" }, { label: "Targets" }, { label: "Parameters" }, { label: "Review" }];
const TABS: TabNavItem[] = [{ label: "Portfolio Manager", active: true }, { label: "History" }];

/** Mirrors PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP/MAX_GROUPS -- a strategy that exceeds
 *  either can't ship on-chain, so the wizard blocks it here instead of failing silently later. */
const MAX_TOKENS_PER_BASKET = 5;
const MAX_BASKETS = 4;

/** Quick-filter badges only surface this curated subset -- the full 40-token list stays reachable
 *  through the search box below. */
const POPULAR_TOKEN_SYMBOLS = ["USDC", "USDT", "DAI", "WETH", "CBETH", "WBTC", "CBBTC"];

export type CreateBasketsPageProps = {
  network: string;
  safeAddress: string;
  baskets: BasketDraft[];
  safeTokens: SafeToken[];
  tokensLoading?: boolean;
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
  onBack,
  onContinue,
}: CreateBasketsPageProps) {
  const [draftBaskets, setDraftBaskets] = useState(baskets);
  const [selectedBasketId, setSelectedBasketId] = useState(baskets[0]?.id);
  const [activeFilters, setActiveFilters] = useState<Set<string>>(new Set());
  const [query, setQuery] = useState("");

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
    saveDraftBaskets(safeAddress, draftBaskets);
  }, [safeAddress, draftBaskets]);

  const selectedBasket = draftBaskets.find((basket) => basket.id === selectedBasketId) ?? draftBaskets[0];
  const assignedAddresses = new Set(draftBaskets.flatMap((basket) => basket.tokenAddresses));

  const visibleTokens = useMemo(() => {
    return safeTokens
      .filter((token) => {
        const matchesFilter = activeFilters.size === 0 || activeFilters.has(token.symbol);
        const matchesQuery =
          query.trim() === "" ||
          token.symbol.toLowerCase().includes(query.toLowerCase()) ||
          token.address.toLowerCase().includes(query.toLowerCase());
        return matchesFilter && matchesQuery;
      })
      .sort((a, b) => b.value - a.value);
  }, [safeTokens, activeFilters, query]);

  const popularTokens = useMemo(
    () =>
      POPULAR_TOKEN_SYMBOLS.map((symbol) => safeTokens.find((t) => t.symbol === symbol)).filter(
        (t): t is SafeToken => t !== undefined,
      ),
    [safeTokens],
  );

  function toggleFilter(symbol: string) {
    setActiveFilters((prev) => {
      const next = new Set(prev);
      if (next.has(symbol)) next.delete(symbol);
      else next.add(symbol);
      return next;
    });
  }

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

  function addBasket() {
    if (draftBaskets.length >= MAX_BASKETS) return;
    const id = `basket-${draftBaskets.length + 1}`;
    setDraftBaskets((prev) => [...prev, { id, name: `Basket ${prev.length + 1}`, color: "#38bdf8", tokenAddresses: [] }]);
    setSelectedBasketId(id);
  }

  const selectedBasketTokens = selectedBasket
    ? safeTokens.filter((t) => selectedBasket.tokenAddresses.includes(t.address))
    : [];
  const selectedBasketValue = selectedBasketTokens.reduce((sum, t) => sum + t.value, 0);
  const managedTokenCount = assignedAddresses.size;

  return (
    <div className="min-h-screen">
      <AppHeader tabs={TABS} network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-5xl px-6 py-8">
        <h1 className="text-2xl font-semibold text-white">Create your baskets</h1>
        <p className="mt-1 text-sm text-gray-400">Create baskets on the left, then choose their tokens from the selected basket.</p>

        <div className="mt-6">
          <WizardStepper steps={WIZARD_STEPS} activeIndex={0} />
        </div>

        <div className="mt-8 grid grid-cols-[280px_1fr] gap-4">
          <div className="space-y-2">
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-semibold text-white">Your baskets</h2>
                <span className="flex h-5 w-5 items-center justify-center rounded-full bg-surface-raised text-xs text-gray-300">
                  {draftBaskets.length}
                </span>
              </div>
              <p className="mt-0.5 text-xs text-gray-500">Select a basket to manage its tokens.</p>
            </div>
            {draftBaskets.map((basket) => {
              const tokens = safeTokens.filter((t) => basket.tokenAddresses.includes(t.address));
              const value = tokens.reduce((sum, t) => sum + t.value, 0);
              return (
                <GroupSummaryCard
                  key={basket.id}
                  compact
                  onClick={() => setSelectedBasketId(basket.id)}
                  group={{
                    id: basket.id,
                    name: basket.name,
                    color: basket.color,
                    tokens,
                    trailing: { kind: "amount", value },
                    selected: basket.id === selectedBasketId,
                  }}
                />
              );
            })}
            <AddBasketButton onClick={addBasket} disabled={draftBaskets.length >= MAX_BASKETS} />
            <p className="pt-2 text-xs text-gray-600">Each token can only belong to one basket.</p>
            {draftBaskets.length >= MAX_BASKETS && (
              <InfoBanner>A strategy can hold at most {MAX_BASKETS} baskets.</InfoBanner>
            )}
          </div>

          {selectedBasket && (
            <div className="space-y-4 rounded-xl border border-border bg-surface-card p-5">
              <BasketPanelHeader
                name={selectedBasket.name}
                color={selectedBasket.color}
                tokenCount={selectedBasketTokens.length}
                totalValue={selectedBasketValue}
                onRename={(name) => renameBasket(selectedBasket.id, name)}
              />

              <div>
                <p className="mb-2 text-xs text-gray-500">Tokens in this basket</p>
                <div className="flex flex-wrap gap-1.5">
                  {selectedBasketTokens.length === 0 && <span className="text-xs text-gray-600">No tokens yet.</span>}
                  {selectedBasketTokens.map((token) => (
                    <TokenChip
                      key={token.address}
                      token={token}
                      variant="removable"
                      value={token.value}
                      onRemove={() => toggleTokenInSelectedBasket(token.address)}
                    />
                  ))}
                </div>
              </div>

              {selectedBasket.tokenAddresses.length >= MAX_TOKENS_PER_BASKET && (
                <InfoBanner>A basket can hold at most {MAX_TOKENS_PER_BASKET} tokens.</InfoBanner>
              )}

              <div>
                <p className="mb-2 text-xs text-gray-500">Add tokens</p>
                <SearchInput
                  placeholder="Search by token name or address"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {popularTokens.map((token) => (
                    <TokenChip
                      key={token.address}
                      token={token}
                      variant="toggle"
                      selected={activeFilters.has(token.symbol)}
                      onToggle={() => toggleFilter(token.symbol)}
                    />
                  ))}
                </div>
              </div>

              <div className="max-h-64 space-y-1 overflow-y-auto">
                {tokensLoading && <p className="text-xs text-gray-500">Loading Safe balances…</p>}
                {!tokensLoading &&
                  visibleTokens.map((token) => (
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
            summary={`${draftBaskets.length} baskets · ${managedTokenCount} managed tokens`}
            continueLabel="Continue to targets"
            showBack
            onBack={onBack}
            onContinue={onContinue}
            continueDisabled={managedTokenCount === 0}
          />
        </div>
      </div>
    </div>
  );
}
