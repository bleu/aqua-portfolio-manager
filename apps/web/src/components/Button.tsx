"use client";

import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary";
  /** "lg" for a wide standalone CTA (e.g. an empty-state's primary action). Default "default". */
  size?: "default" | "lg";
};

/** Shared button primitive. `primary` is the filled white CTA; `secondary` is the outlined one (e.g. a wizard's "Back"). */
export function Button({ variant = "primary", size = "default", className, ...rest }: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center rounded-[10px] py-3 text-base font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-not-allowed disabled:opacity-50",
        size === "default" ? "px-6" : "px-14",
        variant === "primary" && "bg-white text-surface hover:bg-gray-200 active:bg-gray-400",
        variant === "secondary" && "border border-border bg-transparent text-white hover:bg-surface-raised",
        className,
      )}
      {...rest}
    />
  );
}
