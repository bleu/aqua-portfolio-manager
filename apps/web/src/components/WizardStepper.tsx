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
            <div className="flex items-center gap-2">
              <span
                className={cn(
                  "flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold",
                  state === "complete" && "bg-accent text-white",
                  state === "active" && "bg-accent text-white",
                  state === "upcoming" && "border border-border text-gray-500",
                )}
              >
                {state === "complete" ? "✓" : index + 1}
              </span>
              <span className={cn("text-sm", state === "upcoming" ? "text-gray-500" : "text-gray-100")}>
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
