import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary";
};

/** Shared button primitive. `primary` is the filled white CTA; `secondary` is the outlined one (e.g. a wizard's "Back"). */
export function Button({ variant = "primary", className, ...rest }: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center rounded-[10px] px-6 py-3 text-base font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-not-allowed disabled:opacity-50",
        variant === "primary" && "bg-white text-surface hover:bg-gray-200 active:bg-gray-400",
        variant === "secondary" && "border border-border bg-transparent text-white hover:bg-surface-raised",
        className,
      )}
      {...rest}
    />
  );
}
