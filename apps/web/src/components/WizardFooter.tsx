import { Button } from "./Button";

export type WizardFooterProps = {
  summary: string;
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
  return (
    <div className="flex items-center justify-between border-t border-border pt-4">
      {showBack ? (
        <Button variant="secondary" onClick={onBack}>
          Back
        </Button>
      ) : (
        <span />
      )}
      <div className="flex items-center gap-4">
        <span className="text-xs text-gray-500">{summary}</span>
        <Button onClick={onContinue} disabled={continueDisabled}>
          {continueLabel}
        </Button>
      </div>
    </div>
  );
}
