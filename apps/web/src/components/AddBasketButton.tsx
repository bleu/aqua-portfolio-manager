"use client";

export type AddBasketButtonProps = {
  disabled?: boolean;
  onClick?: () => void;
};

/** The dashed "+ Add basket" action at the bottom of the basket list. */
export function AddBasketButton({ disabled, onClick }: AddBasketButtonProps) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="flex w-full items-center justify-center gap-1.5 rounded-lg border border-dashed border-border py-2.5 text-sm font-medium text-gray-400 transition-colors hover:border-accent hover:text-accent disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-border disabled:hover:text-gray-400"
    >
      <span aria-hidden="true">+</span> Add basket
    </button>
  );
}
