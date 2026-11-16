import { Button } from "./Button";

export type WizardFooterProps = {
  /** Targets and Parameters dropped this per the design's own call: the status it would repeat
   *  (allocation match/mismatch, which fields are filled) already shows inline above the footer. */
  summary?: string;
  continueLabel: string;
  onBack?: () => void;
  onContinue?: () => void;
  /** Disables the continue action (e.g. nothing selected yet). */
  continueDisabled?: boolean;
  /** First step has no Back action. */
  showBack?: boolean;
};

/** Back button + running summary + primary CTA, reused unchanged across every wizard step. */
export function WizardFooter({
  summary,
  continueLabel,
  onBack,
  onContinue,
  continueDisabled,
  showBack = true,
}: WizardFooterProps) {
  // Earlier doc here (node 398:5029) read Figma's footer as a full-bleed tinted bar with no
  // border-radius, deliberately kept from becoming a standalone panel. Direct comparison against
  // the real flow screens (node 680:20012, "Total allocation" on Baskets-Filled) shows a rounded
  // standalone panel instead -- that full-bleed reading did not hold up and is replaced here, not
  // just restyled. Continue uses accent (see Button's own doc comment for why that's correct here,
  // not plain white).
  return (
    <div className="flex items-center justify-between rounded-[30px] border border-border/60 bg-surface-card p-6">
      {showBack ? (
        <Button variant="secondary" onClick={onBack}>
          Back
        </Button>
      ) : (
        <span />
      )}
      <div className="flex items-center gap-4">
        {summary && <span className="text-xs text-gray-500">{summary}</span>}
        <Button variant="accent" onClick={onContinue} disabled={continueDisabled}>
          {continueLabel}
        </Button>
      </div>
    </div>
  );
}
