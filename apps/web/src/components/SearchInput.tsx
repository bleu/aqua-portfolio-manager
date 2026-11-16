"use client";

import type { InputHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

export type SearchInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, "type">;

/** The "Search tokens" field on the Baskets step -- a 60px-tall fully-rounded pill per the Round 2
 *  design spec (artifact `.row` search field, Step1_Baskets_Filled.dc.html), not a small rectangle. */
export function SearchInput({ className, ...rest }: SearchInputProps) {
  return (
    <div className={cn("relative w-[320px] max-w-full", className)}>
      <span className="pointer-events-none absolute left-5 top-1/2 -translate-y-1/2 text-gray-500" aria-hidden="true">
        <svg width="18" height="18" viewBox="0 0 14 14" fill="none">
          <circle cx="6" cy="6" r="4.5" stroke="currentColor" strokeWidth="1.3" />
          <path d="M9.5 9.5L13 13" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
        </svg>
      </span>
      <input
        type="search"
        className="h-[60px] w-full rounded-[30px] border border-transparent bg-[#1d2024] py-2 pl-12 pr-5 text-sm text-gray-200 placeholder:text-gray-500 focus:border-accent focus:outline-none"
        {...rest}
      />
    </div>
  );
}
