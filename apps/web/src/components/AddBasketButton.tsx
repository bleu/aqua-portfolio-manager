"use client";

export type AddBasketButtonProps = {
  disabled?: boolean;
  onClick?: () => void;
};

/** The solid "+ Add basket" pill at the bottom of the basket list -- matches the Claude Artifact's
 *  "Baskets · filled" mockup (project/Step1_Baskets_Filled.dc.html, `.btn.b-solid`), not the
 *  earlier dashed-outline ghost button. */
export function AddBasketButton({ disabled, onClick }: AddBasketButtonProps) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="flex h-12 items-center justify-center gap-2 rounded-full bg-accent px-7 text-[15px] font-semibold text-[#0b0d10] transition-colors hover:bg-accent/90 disabled:cursor-not-allowed disabled:opacity-40"
    >
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M12 5v14M5 12h14" />
      </svg>
      Add basket
    </button>
  );
}
