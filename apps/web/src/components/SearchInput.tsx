"use client";

import type { InputHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

export type SearchInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, "type">;

/** The "Search by token name or address" field above the token-filter row. */
export function SearchInput({ className, ...rest }: SearchInputProps) {
  return (
    <div className={cn("relative", className)}>
      <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" aria-hidden="true">
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
          <circle cx="6" cy="6" r="4.5" stroke="currentColor" strokeWidth="1.3" />
          <path d="M9.5 9.5L13 13" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
        </svg>
      </span>
      <input
        type="search"
        className="w-full rounded-lg border border-border bg-surface-raised py-2 pl-9 pr-3 text-sm text-gray-200 placeholder:text-gray-500 focus:border-accent focus:outline-none"
        {...rest}
      />
    </div>
  );
}
