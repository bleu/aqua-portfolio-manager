import { cn } from "@/lib/cn";

export type SignatureProgressBarProps = {
  total: number;
  signed: number;
  className?: string;
};

/** A discrete N-segment bar, one segment per required signer -- not the same as the existing
 *  continuous ProgressBar, which fills a single 0-1 fraction rather than N separate steps. */
export function SignatureProgressBar({ total, signed, className }: SignatureProgressBarProps) {
  const segments = Array.from({ length: Math.max(total, 1) }, (_, i) => i < signed);
  return (
    <div
      className={cn("flex gap-1.5", className)}
      role="progressbar"
      aria-valuenow={signed}
      aria-valuemin={0}
      aria-valuemax={total}
    >
      {segments.map((filled, i) => (
        <div key={i} className={cn("h-1.5 flex-1 rounded-full", filled ? "bg-accent" : "bg-border")} />
      ))}
    </div>
  );
}
