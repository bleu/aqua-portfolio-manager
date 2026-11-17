import { Badge } from "./Badge";
import { Identicon } from "./Identicon";
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
 *  The icon is a deterministic per-address identicon (lib/identicon.ts), not a fetched "real Safe
 *  avatar": the Safe Apps SDK's own getInfo() response has no avatar/logo field at all -- Safe's
 *  own UI generates the same kind of client-side blockie from the address, there's no separate
 *  server-provided image to fetch here either. An earlier flat placeholder square is replaced by
 *  this, not supplemented with a loading/fallback state, since there's only ever this one source. */
export function AddressBadge({ label, address }: AddressBadgeProps) {
  return (
    <Badge
      icon={<Identicon address={address} size={24} className="shrink-0 rounded-[8px]" />}
      className="gap-2 rounded-[30px] border-[#292c30] bg-surface-raised p-3 text-sm font-normal text-white"
    >
      {label} · {truncateAddress(address)}
    </Badge>
  );
}
