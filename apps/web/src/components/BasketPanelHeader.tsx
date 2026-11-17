"use client";

import { useState } from "react";

export type BasketPanelHeaderProps = {
  name: string;
  onRename?: (name: string) => void;
};

/** The selected basket's panel header: name (click the pencil to rename inline). No colored dot
 *  and no "Selected basket" pill -- the Claude Artifact's own right panel
 *  (project/Step1_Baskets_Filled.dc.html) has neither; the basket being edited is already obvious
 *  from its own card's accent-colored border in the left column. */
export function BasketPanelHeader({ name, onRename }: BasketPanelHeaderProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [draftName, setDraftName] = useState(name);

  function commitRename() {
    const trimmed = draftName.trim();
    if (trimmed && trimmed !== name) onRename?.(trimmed);
    setIsEditing(false);
  }

  return (
    <div className="flex items-center gap-2">
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
          className="rounded border border-border bg-transparent px-1 text-xl font-semibold text-white outline-none"
        />
      ) : (
        <h2 className="text-xl font-semibold text-white">{name}</h2>
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
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M4 20l1-4L16 5l3 3L8 19l-4 1zM14 7l3 3" />
        </svg>
      </button>
    </div>
  );
}
