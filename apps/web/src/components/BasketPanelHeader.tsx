"use client";

import { useState } from "react";
import { Badge } from "./Badge";
import { formatUsd } from "@/lib/format";

export type BasketPanelHeaderProps = {
  name: string;
  color: string;
  tokenCount: number;
  totalValue: number;
  onRename?: (name: string) => void;
};

/** The selected basket's panel header: color dot + name (click the pencil to rename inline) + token count/value + a "Selected basket" badge. */
export function BasketPanelHeader({ name, color, tokenCount, totalValue, onRename }: BasketPanelHeaderProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [draftName, setDraftName] = useState(name);

  function commitRename() {
    const trimmed = draftName.trim();
    if (trimmed && trimmed !== name) onRename?.(trimmed);
    setIsEditing(false);
  }

  return (
    <div className="flex items-center justify-between">
      <div>
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: color }} />
          {isEditing ? (
            <input
              autoFocus
              value={draftName}
              onChange={(e) => setDraftName(e.target.value)}
              onBlur={commitRename}
              onKeyDown={(e) => {
                if (e.key === "Enter") commitRename();
                if (e.key === "Escape") {
                  setDraftName(name);
                  setIsEditing(false);
                }
              }}
              className="rounded border border-border bg-transparent px-1 text-base font-semibold text-white outline-none"
            />
          ) : (
            <h3 className="text-base font-semibold text-white">{name}</h3>
          )}
          <button
            type="button"
            onClick={() => {
              setDraftName(name);
              setIsEditing(true);
            }}
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
      <Badge dotColor="#6366f1" className="border-accent/40 bg-accent/10 text-accent">
        Selected basket
      </Badge>
    </div>
  );
}
