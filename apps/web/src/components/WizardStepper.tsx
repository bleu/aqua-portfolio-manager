import { cn } from "@/lib/cn";

export type WizardStep = {
  label: string;
};

export type WizardStepperProps = {
  steps: WizardStep[];
  /** 0-based index of the current step. */
  activeIndex: number;
};

/** The 4-step Baskets/Targets/Parameters/Review indicator. Reused unchanged across every wizard step page. */
export function WizardStepper({ steps, activeIndex }: WizardStepperProps) {
  return (
    <ol className="flex items-center justify-center gap-3">
      {steps.map((step, index) => {
        const state = index < activeIndex ? "complete" : index === activeIndex ? "active" : "upcoming";
        return (
          <li key={step.label} className="flex items-center gap-3">
            <div
              className={cn(
                "flex items-center gap-2 rounded-lg",
                state === "active" && "border border-accent/40 bg-accent/10 px-2.5 py-1",
              )}
            >
              <span
                className={cn(
                  "flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold",
                  state === "complete" && "border border-accent/40 bg-accent/10 text-accent",
                  state === "active" && "bg-accent text-white",
                  state === "upcoming" && "border border-border text-gray-500",
                )}
              >
                {state === "complete" ? "✓" : index + 1}
              </span>
              <span
                className={cn(
                  "text-sm",
                  state === "complete" && "text-accent",
                  state === "active" && "text-white",
                  state === "upcoming" && "text-gray-500",
                )}
              >
                {step.label}
              </span>
            </div>
            {index < steps.length - 1 && <span className="h-px w-8 bg-border" aria-hidden="true" />}
          </li>
        );
      })}
    </ol>
  );
}
