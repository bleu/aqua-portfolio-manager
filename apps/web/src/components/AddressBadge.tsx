import { Badge } from "./Badge";
import { truncateAddress } from "@/lib/format";

export type AddressBadgeProps = {
  /** e.g. "Safe" */
  label: string;
  address: string;
};

/** The truncated Safe-address pill shown in the app header, e.g. "Safe · 0x71A4...9F2C". Matches
 *  Figma's "wallet-indicator" (node 546:25620, confirmed on the Baskets-Filled flow screen): bg
 *  #1e2123 (surface-raised), border #292c30, 30px radius, 12px padding, 8px gap, Inter Regular
 *  14px white text, and a leading 24px rounded-[8px] avatar icon.
 *
 *  The avatar itself is a flat placeholder, not Figma's real reference image -- this app has no
 *  per-address avatar/blockie generator yet, so there's nothing real to render there. Flagging
 *  rather than fabricating a fake identicon. */
export function AddressBadge({ label, address }: AddressBadgeProps) {
  return (
    <Badge
      icon={<span className="h-6 w-6 shrink-0 rounded-[8px] bg-accent/30" />}
      className="gap-2 rounded-[30px] border-[#292c30] bg-surface-raised p-3 text-sm font-normal text-white"
    >
      {label} · {truncateAddress(address)}
    </Badge>
  );
}
