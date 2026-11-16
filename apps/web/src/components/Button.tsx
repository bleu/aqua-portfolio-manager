"use client";

import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "accent";
  /** "lg" for a wide standalone CTA (e.g. an empty-state's primary action). Default "default". */
  size?: "default" | "lg";
};

/** Shared button primitive. `primary` is the filled white CTA; `secondary` is Trim's
 *  "Actions/Button/Secondary" -- a solid dark pill (e.g. a wizard's "Back"), confirmed directly
 *  against the Baskets-Filled flow screen (node 680:20284): earlier doc here claimed this was an
 *  outlined, boxy button and that a wizard's "Continue" stayed plain white -- that reading did not
 *  hold up against the real flow screens and is corrected here, not just restyled. `accent` is
 *  Trim's "Actions/Button/Primary" component -- a mint gradient pill, confirmed on the landing
 *  page's own header/hero buttons (nodes 680:20947, 680:20953) *and* on every wizard step's own
 *  "Continue" (node 680:20285 on the same Baskets-Filled screen) -- it is the one primary CTA
 *  treatment across the app, not reserved for a single highest-emphasis action. */
export function Button({ variant = "primary", size = "default", className, ...rest }: ButtonProps) {
  const paddingX = variant === "primary" && size !== "default" ? "px-14" : "px-[18px]";
  return (
    <button
      className={cn(
        "inline-flex h-[48px] items-center justify-center gap-2 rounded-full text-base font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-not-allowed disabled:opacity-50",
        paddingX,
        variant === "primary" && "bg-white text-surface hover:bg-gray-200 active:bg-gray-400",
        variant === "secondary" && "bg-[#202328] text-white hover:bg-[#2a2e34]",
        // font-[590] is confirmed on three separate instances of this component now (not a
        // one-off reading) -- reverting an earlier swap to font-semibold (600) that was chasing
        // a "too thick" report without confirming 590 was actually wrong.
        variant === "accent" &&
          "bg-gradient-to-b from-[#f0f9fa] to-accent text-[#0a0c16] text-[15px] font-[590] hover:opacity-90 active:opacity-80",
        className,
      )}
      {...rest}
    />
  );
}
