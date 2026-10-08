"use client";

import { Badge } from "./Badge";
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
  onToggle?: () => void;
};

/** One row in the Safe's full token list: checkbox, icon, name + address, balance + value, "Added" state. */
export function TokenListRow({ token, balance, value, added, highlighted, onToggle }: TokenListRowProps) {
  return (
    <label
      className={cn(
        "flex cursor-pointer items-center gap-3 rounded-lg border border-transparent px-3 py-2.5 transition-colors hover:bg-surface-raised",
        highlighted && "border-accent bg-accent/10",
      )}
    >
      <input
        type="checkbox"
        checked={added}
        onChange={onToggle}
        className="h-4 w-4 shrink-0 rounded border-border bg-surface-raised accent-accent"
      />
      <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-accent/30 text-xs font-semibold text-accent">
        {token.symbol.slice(0, 1)}
      </span>
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
