"use client";

import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cn } from "@/lib/cn";

export type IconButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode;
  "aria-label": string;
};

/** A square icon-only button -- the dashboard's "···" overflow menu trigger. No existing `Button`
 *  usage so far is icon-only, so this stays a separate, small primitive rather than overloading
 *  `Button` with a visible-text-optional mode. */
export function IconButton({ children, className, ...rest }: IconButtonProps) {
  return (
    <button
      type="button"
      className={cn(
        "flex size-10 items-center justify-center rounded-[10px] border border-border bg-transparent text-gray-300 transition-colors hover:bg-surface-raised disabled:cursor-not-allowed disabled:opacity-50",
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  );
}
