"use client";

import { cn } from "@/lib/cn";

export type SegmentedControlProps<T extends string> = {
  options: readonly T[];
  value: T;
  onChange: (value: T) => void;
  className?: string;
};

/** A plain single-select pill row with no trailing custom-value input -- the dashboard's time-range
 *  selector (24h/7d/30d/90d/All). `ChoicePillGroup` (BLEUDEV-415) looked like a fit for this at
 *  first, but it's numeric-only with a mandatory "Custom %" input tacked on, which doesn't apply
 *  to non-numeric range labels -- this is a separate, smaller primitive rather than a forced
 *  generalization of that one. */
export function SegmentedControl<T extends string>({ options, value, onChange, className }: SegmentedControlProps<T>) {
  return (
    <div className={cn("flex items-center gap-1", className)}>
      {options.map((option) => {
        const selected = value === option;
        return (
          <button
            key={option}
            type="button"
            onClick={() => onChange(option)}
            aria-pressed={selected}
            className={cn(
              "rounded-lg border px-2.5 py-1 text-xs font-medium transition-colors",
              selected
                ? "border-accent bg-accent/10 text-accent"
                : "border-transparent text-gray-400 hover:text-gray-200",
            )}
          >
            {option}
          </button>
        );
      })}
    </div>
  );
}
