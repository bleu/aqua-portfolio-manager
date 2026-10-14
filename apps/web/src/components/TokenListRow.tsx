"use client";

import { Badge } from "./Badge";
import { TokenIcon } from "./TokenIcon";
import { cn } from "@/lib/cn";
import { formatUsd, truncateAddress } from "@/lib/format";
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
};

/** One row in the Safe's full token list: checkbox, icon, name + address, balance + value, "Added" state. */
export function TokenListRow({ token, balance, value, added, highlighted, disabled, onToggle }: TokenListRowProps) {
  const blocked = disabled && !added;
  return (
    <label
      className={cn(
        "flex cursor-pointer items-center gap-3 rounded-lg border border-transparent px-3 py-2.5 transition-colors hover:bg-surface-raised",
        highlighted && "border-accent bg-accent/10",
        blocked && "cursor-not-allowed opacity-50 hover:bg-transparent",
      )}
    >
      <input
        type="checkbox"
        checked={added}
        disabled={blocked}
        onChange={onToggle}
        className="h-4 w-4 shrink-0 rounded border-border bg-surface-raised accent-accent disabled:cursor-not-allowed"
      />
      <TokenIcon symbol={token.symbol} iconUrl={token.iconUrl} size={28} className="text-xs" />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium text-gray-100">{token.symbol}</span>
        <span className="block truncate text-xs text-gray-500">{truncateAddress(token.address)}</span>
      </span>
      <span className="shrink-0 text-right">
        <span className="block text-sm text-gray-200">{balance.toLocaleString("en-US")}</span>
        <span className="block text-xs text-gray-500">{formatUsd(value)}</span>
      </span>
      {added && <Badge className="shrink-0 border-positive/40 bg-positive/10 text-positive">Added</Badge>}
    </label>
  );
}
