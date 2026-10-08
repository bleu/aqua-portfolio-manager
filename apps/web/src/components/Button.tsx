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
        "inline-flex items-center justify-center rounded-lg px-5 py-2.5 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50",
        variant === "primary" && "bg-white text-surface hover:bg-gray-200",
        variant === "secondary" && "border border-border bg-transparent text-gray-200 hover:bg-surface-raised",
        className,
      )}
      {...rest}
    />
  );
}
