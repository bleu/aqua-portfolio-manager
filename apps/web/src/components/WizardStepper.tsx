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
 *  step page. Matches the Claude Artifact exactly (confirmed across Step1_Baskets_Filled.dc.html,
 *  where steps after the active one are "upcoming", and Step4_Risk_Modal.dc.html, where the 3
 *  steps before Review are "complete"): every pill shares the same background (#16191c); only the
 *  ACTIVE step gets the accent-filled circle + white label. A completed step gets a mid-gray
 *  circle (#6d7378) with a checkmark glyph and a lighter-gray label (#c7cbcf) -- visibly distinct
 *  from both the active step and an upcoming one (#24282c circle / #9aa0a5 label). An earlier
 *  version of this component gave completed steps the same accent fill as the active step,
 *  confirmed as a bug against the artifact, not a deliberate reading of Figma node 75:2. */
export function WizardStepper({ steps, activeIndex }: WizardStepperProps) {
  return (
    <ol className="flex w-full items-center gap-3">
      {steps.map((step, index) => {
        const state = index < activeIndex ? "complete" : index === activeIndex ? "active" : "upcoming";
        return (
          <li key={step.label} className="flex flex-1 items-center gap-3 last:flex-none">
            <div className="flex shrink-0 items-center gap-2.5 rounded-full bg-[#16191c] p-3">
              <span
                className={cn(
                  "flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
                  state === "active"
                    ? "bg-accent text-[#0b1514]"
                    : state === "complete"
                      ? "bg-[#6d7378] text-[#15171a]"
                      : "bg-[#24282c] text-[#9aa0a5]",
                )}
              >
                {state === "complete" ? (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d="M6 12l4 4 8-9" />
                  </svg>
                ) : (
                  index + 1
                )}
              </span>
              <span
                className={cn(
                  "whitespace-nowrap text-[17px]",
                  state === "active" ? "text-white" : state === "complete" ? "text-[#c7cbcf]" : "text-[#9aa0a5]",
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
