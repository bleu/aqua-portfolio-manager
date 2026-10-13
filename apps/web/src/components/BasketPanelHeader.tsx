"use client";

import { Badge } from "./Badge";
import { formatUsd } from "@/lib/format";

export type BasketPanelHeaderProps = {
  name: string;
  color: string;
  tokenCount: number;
  totalValue: number;
  onEdit?: () => void;
};

/** The selected basket's panel header: color dot + name + edit affordance + token count/value + a "Selected basket" badge. */
export function BasketPanelHeader({ name, color, tokenCount, totalValue, onEdit }: BasketPanelHeaderProps) {
  return (
    <div className="flex items-center justify-between">
      <div>
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: color }} />
          <h3 className="text-base font-semibold text-white">{name}</h3>
          <button
            type="button"
            onClick={onEdit}
            aria-label={`Edit ${name}`}
            className="text-gray-500 hover:text-gray-300"
          >
            ✎
          </button>
        </div>
        <p className="mt-1 text-xs text-gray-500">
          {tokenCount} {tokenCount === 1 ? "token" : "tokens"} · {formatUsd(totalValue)} current value
        </p>
      </div>
      <Badge className="border-accent/40 bg-accent/10 text-accent">Selected basket</Badge>
    </div>
  );
}
