import type { ReactNode } from "react";

export type DetailRowProps = {
  label: string;
  value: ReactNode;
};

/** A plain label-left/value-right row -- Transaction Details sections across the Review,
 *  waiting-for-signatures, and activated pages. No color dot, no token list, just two text nodes. */
export function DetailRow({ label, value }: DetailRowProps) {
  return (
    <div className="flex items-center justify-between py-2 text-sm">
      <span className="text-gray-500">{label}</span>
      <span className="text-white">{value}</span>
    </div>
  );
}
