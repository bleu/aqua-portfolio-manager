"use client";

export type AddBasketButtonProps = {
  onClick?: () => void;
};

/** The dashed "+ Add basket" action at the bottom of the basket list. */
export function AddBasketButton({ onClick }: AddBasketButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center justify-center gap-1.5 rounded-lg border border-dashed border-border py-2.5 text-sm font-medium text-gray-400 transition-colors hover:border-accent hover:text-accent"
    >
      <span aria-hidden="true">+</span> Add basket
    </button>
  );
}
