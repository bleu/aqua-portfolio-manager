import { CheckIcon, XIcon } from "./icons";
import { cn } from "@/lib/cn";

export type StatusIconProps = {
  variant: "pending" | "success" | "error";
  className?: string;
};

const VARIANT_STYLES = {
  pending: "border-amber-400/30 bg-amber-400/10 text-amber-400",
  success: "border-positive/30 bg-positive/10 text-positive",
  error: "border-red-400/30 bg-red-400/10 text-red-400",
} as const;

/** The round status icon at the top of post-wizard pages -- pending (waiting for signatures),
 *  success (activated), or error (a failed/rejected transaction, not yet pictured in any design
 *  but kept as a real variant rather than hardcoded to just the pending look). */
export function StatusIcon({ variant, className }: StatusIconProps) {
  return (
    <span
      className={cn(
        "flex size-14 shrink-0 items-center justify-center rounded-full border",
        VARIANT_STYLES[variant],
        className,
      )}
    >
      {variant === "pending" && (
        <span className="flex items-center gap-1" aria-hidden="true">
          <span className="size-1.5 animate-pulse rounded-full bg-current [animation-delay:-0.3s]" />
          <span className="size-1.5 animate-pulse rounded-full bg-current [animation-delay:-0.15s]" />
          <span className="size-1.5 animate-pulse rounded-full bg-current" />
        </span>
      )}
      {variant === "success" && <CheckIcon className="size-6" />}
      {variant === "error" && <XIcon className="size-6" />}
    </span>
  );
}
