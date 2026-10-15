"use client";

import { TokenIcon } from "./TokenIcon";
import { cn } from "@/lib/cn";
import type { Token } from "@/lib/types";

export type TokenChipProps = {
  token: Token;
  /** display: static read-only chip. toggle: clickable filter pill. removable: has an (x) to drop the token. */
  variant?: "display" | "toggle" | "removable";
  /** Only meaningful for variant="toggle". */
  selected?: boolean;
  onToggle?: () => void;
  onRemove?: () => void;
  /** display only: hide the leading icon and border for a compact context (e.g. the allocation-comparison card). Default true (icon shown). */
  showIcon?: boolean;
  className?: string;
};

/** Token icon + ticker chip, shared across every page that lists or picks tokens. */
export function TokenChip({
  token,
  variant = "display",
  selected,
  onToggle,
  onRemove,
  showIcon = true,
  className,
}: TokenChipProps) {
  const base = "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium";

  if (variant === "toggle") {
    return (
      <button
        type="button"
        onClick={onToggle}
        aria-pressed={selected}
        className={cn(
          base,
          "transition-colors",
          selected ? "border-accent bg-accent/20 text-white" : "border-border bg-surface-raised text-gray-300",
          className,
        )}
      >
        <TokenIcon symbol={token.symbol} iconUrl={token.iconUrl} />
        {token.symbol}
      </button>
    );
  }

  if (variant === "removable") {
    return (
      <span className={cn(base, "border-border bg-surface-raised text-gray-200", className)}>
        <TokenIcon symbol={token.symbol} iconUrl={token.iconUrl} />
        {token.symbol}
        <button
          type="button"
          onClick={onRemove}
          aria-label={`Remove ${token.symbol}`}
          className="ml-0.5 text-gray-500 hover:text-gray-200"
        >
          ×
        </button>
      </span>
    );
  }

  return (
    <span
      className={cn(
        base,
        showIcon ? "border-border bg-surface-raised text-gray-300" : "border-transparent bg-surface-raised text-gray-300",
        className,
      )}
    >
      {showIcon && <TokenIcon symbol={token.symbol} iconUrl={token.iconUrl} />}
      {token.symbol}
    </span>
  );
}
