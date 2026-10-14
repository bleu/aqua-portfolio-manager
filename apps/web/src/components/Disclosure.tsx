"use client";

import { useState } from "react";
import type { ReactNode } from "react";
import { ChevronDownIcon } from "./icons";
import { cn } from "@/lib/cn";

export type DisclosureProps = {
  label: string;
  children: ReactNode;
  defaultOpen?: boolean;
  className?: string;
};

/** A collapsible row with a chevron -- "How price protection works" / "View fees and permissions",
 *  shared across the wizard's parameters, review, and post-transaction pages. */
export function Disclosure({ label, children, defaultOpen, className }: DisclosureProps) {
  const [open, setOpen] = useState(defaultOpen ?? false);
  return (
    <div className={cn("rounded-lg border border-border bg-surface-raised", className)}>
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        aria-expanded={open}
        className="flex w-full items-center justify-between px-4 py-3 text-left text-sm font-medium text-white"
      >
        {label}
        <ChevronDownIcon className={cn("size-4 shrink-0 text-gray-400 transition-transform", open && "rotate-180")} />
      </button>
      {open && <div className="px-4 pb-3 text-sm text-gray-400">{children}</div>}
    </div>
  );
}
