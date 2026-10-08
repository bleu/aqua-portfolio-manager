import { Badge } from "./Badge";
import { truncateAddress } from "@/lib/format";

export type AddressBadgeProps = {
  /** e.g. "Safe" */
  label: string;
  address: string;
};

/** The truncated Safe-address pill shown in the app header, e.g. "Safe · 0x71A4...9F2C". */
export function AddressBadge({ label, address }: AddressBadgeProps) {
  return (
    <Badge>
      {label} · {truncateAddress(address)}
    </Badge>
  );
}
