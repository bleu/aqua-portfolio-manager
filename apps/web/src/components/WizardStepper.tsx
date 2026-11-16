import { cn } from "@/lib/cn";

export type WizardStep = {
  label: string;
};

export type WizardStepperProps = {
  steps: WizardStep[];
  /** 0-based index of the current step. */
  activeIndex: number;
};

/** The 4-step Baskets/Targets/Parameters/Review indicator. Reused unchanged across every wizard
 *  step page. Matches Figma's Navigation/Progress/Bar (node 500:20298, Baskets-Filled flow
 *  screen): each step is its own pill, not a bare circle + label, joined by a connector line
 *  that stretches to fill the bar -- supersedes an earlier, narrower circle-only reading. */
export function WizardStepper({ steps, activeIndex }: WizardStepperProps) {
  return (
    <ol className="flex w-full items-center gap-3">
      {steps.map((step, index) => {
        const state = index < activeIndex ? "complete" : index === activeIndex ? "active" : "upcoming";
        const isCurrentOrDone = state !== "upcoming";
        return (
          <li key={step.label} className="flex flex-1 items-center gap-3 last:flex-none">
            <div
              className={cn(
                "flex shrink-0 items-center gap-2.5 rounded-full p-3",
                isCurrentOrDone ? "bg-surface-raised" : "bg-gradient-to-r from-white/[0.02] to-white/[0.04]",
              )}
            >
              <span
                className={cn(
                  "flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
                  isCurrentOrDone ? "bg-accent text-[#0b1514]" : "bg-gradient-to-r from-white/[0.02] to-white/[0.04] text-gray-400",
                )}
              >
                {state === "complete" ? "✓" : index + 1}
              </span>
              {/* Figma's own reference (node 75:2) gives a completed step's label the accent
                  color, not plain white -- confirmed on "Baskets"/"Targets" there, though the
                  step immediately before the active one ("Parameters") rendered plain white in
                  that same reference, which reads as an authoring inconsistency rather than a
                  deliberate "last completed step" rule, so not replicated here. */}
              <span
                className={cn(
                  "whitespace-nowrap text-[17px]",
                  state === "upcoming" ? "text-gray-400" : state === "complete" ? "text-accent" : "text-[#fafbea]",
                )}
              >
                {step.label}
              </span>
            </div>
            {index < steps.length - 1 && <span className="h-px min-w-8 flex-1 bg-border" aria-hidden="true" />}
          </li>
        );
      })}
    </ol>
  );
}
