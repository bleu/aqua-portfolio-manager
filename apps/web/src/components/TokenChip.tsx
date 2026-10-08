"use client";

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
  className?: string;
};

function TokenIcon({ symbol }: { symbol: string }) {
  return (
    <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-accent/30 text-[10px] font-semibold text-accent">
      {symbol.slice(0, 1)}
    </span>
  );
}

/** Token icon + ticker chip, shared across every page that lists or picks tokens. */
export function TokenChip({ token, variant = "display", selected, onToggle, onRemove, className }: TokenChipProps) {
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
        <TokenIcon symbol={token.symbol} />
        {token.symbol}
      </button>
    );
  }

  if (variant === "removable") {
    return (
      <span className={cn(base, "border-border bg-surface-raised text-gray-200", className)}>
        <TokenIcon symbol={token.symbol} />
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
    <span className={cn(base, "border-border bg-surface-raised text-gray-300", className)}>
      <TokenIcon symbol={token.symbol} />
      {token.symbol}
    </span>
  );
}
