"use client";

import { TokenIcon } from "./TokenIcon";
import { cn } from "@/lib/cn";
import { formatUsd } from "@/lib/format";
import type { Token } from "@/lib/types";

export type TokenListRowProps = {
  token: Token;
  balance: number;
  value: number;
  /** Already assigned to a basket. */
  added?: boolean;
  /** Currently being added/highlighted by the picker. */
  highlighted?: boolean;
  /** Basket is already at its token limit -- blocks adding more, but an already-added token stays removable. */
  disabled?: boolean;
  onToggle?: () => void;
  /** No pick control, shows `tokenName` instead of the address tooltip -- the dashboard's
   *  basket-composition rows (BLEUDEV-419), which only ever display, never pick. */
  readOnly?: boolean;
  /** Only shown when `readOnly` -- e.g. "USD Coin" instead of the plain symbol. */
  tokenName?: string;
  /** Only meaningful when `readOnly` -- the owning basket's color, applied to the token's
   *  fallback-avatar icon on the dashboard's basket-composition rows. */
  color?: string;
};

/** One row in the Safe's full token list. Matches the Claude Artifact's own row exactly
 *  (project/Step1_Baskets_Filled.dc.html): icon, symbol, balance + USD value, and a round 40px
 *  button -- grey "+" to add, teal "✕" to remove -- not a checkbox + a separate "Added" badge.
 *  The full address, which the design has no room for, goes in the row's `title` tooltip instead
 *  of a visible second line. */
export function TokenListRow({
  token,
  balance,
  value,
  added,
  highlighted,
  disabled,
  onToggle,
  readOnly,
  tokenName,
  color,
}: TokenListRowProps) {
  const blocked = disabled && !added;

  if (readOnly) {
    return (
      <div
        title={tokenName}
        className="flex h-16 items-center justify-between gap-4 border-t border-[#20242a] px-5 first:border-t-0"
      >
        <span className="flex min-w-0 items-center gap-4">
          <TokenIcon symbol={token.symbol} iconUrl={token.iconUrl} size={40} color={color} />
          <span className="truncate text-base text-white">{token.symbol}</span>
        </span>
        <span className="shrink-0 text-right">
          <span className="block text-sm font-semibold text-white">{balance.toLocaleString("en-US")}</span>
          <span className="block text-xs text-[#8b9096]">{formatUsd(value)}</span>
        </span>
      </div>
    );
  }

  return (
    <button
      type="button"
      title={token.address}
      aria-label={`${added ? "Remove" : "Add"} ${token.symbol}`}
      onClick={onToggle}
      disabled={blocked}
      className={cn(
        "flex w-full items-center gap-3 rounded-lg border border-transparent px-3 py-2.5 text-left transition-colors",
        "hover:bg-surface-raised",
        added && "bg-accent/10",
        highlighted && "border-accent bg-accent/10",
        blocked && "cursor-not-allowed opacity-50 hover:bg-transparent",
      )}
    >
      <TokenIcon symbol={token.symbol} iconUrl={token.iconUrl} size={28} />
      <span className="min-w-0 flex-1 truncate text-sm font-medium text-gray-100">{token.symbol}</span>
      <span className="shrink-0 text-right">
        <span className="block text-sm text-gray-200">{balance.toLocaleString("en-US")}</span>
        <span className="block text-xs text-gray-500">{formatUsd(value)}</span>
      </span>
      <span
        aria-hidden="true"
        className={cn(
          "flex size-10 shrink-0 items-center justify-center rounded-full",
          added ? "bg-accent text-[#0b0d10]" : "bg-[#2a2e33] text-gray-300",
        )}
      >
        {added ? (
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 6l12 12M18 6L6 18" />
          </svg>
        ) : (
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 5v14M5 12h14" />
          </svg>
        )}
      </span>
    </button>
  );
}
