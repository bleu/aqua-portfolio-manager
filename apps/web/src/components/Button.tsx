"use client";

import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "accent";
  /** "lg" for a wide standalone CTA (e.g. an empty-state's primary action). Default "default". */
  size?: "default" | "lg";
};

/** Shared button primitive. `primary` is the filled white CTA; `secondary` is the outlined one
 *  (e.g. a wizard's "Back"); `accent` is Trim's brand-guide "Actions/Button/Primary" component
 *  (node 970:26422) -- a mint gradient pill, for a page's single highest-emphasis action,
 *  distinct from every wizard step's plain white "Continue". */
export function Button({ variant = "primary", size = "default", className, ...rest }: ButtonProps) {
  const paddingX = variant === "accent" ? "px-[18px]" : size === "default" ? "px-6" : "px-14";
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center py-3 text-base font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-not-allowed disabled:opacity-50",
        variant === "accent" ? "rounded-full" : "rounded-[10px]",
        paddingX,
        variant === "primary" && "bg-white text-surface hover:bg-gray-200 active:bg-gray-400",
        variant === "secondary" && "border border-border bg-transparent text-white hover:bg-surface-raised",
        variant === "accent" &&
          "bg-gradient-to-b from-[#f0f9fa] to-accent text-[#0a0c16] text-[15px] font-[590] hover:opacity-90 active:opacity-80",
        className,
      )}
      {...rest}
    />
  );
}
