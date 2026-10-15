import clsx, { type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** clsx plus Tailwind-aware conflict resolution -- a later conflicting utility (e.g. an override
 *  passed via `className`) always wins over an earlier one from the same utility group, instead
 *  of the outcome depending on Tailwind's own generated-CSS order (which plain clsx can't know
 *  about). Caught multiple real bugs where a caller's override silently lost to a component's own
 *  default class (Card's padding/radius, GroupSummaryCard's selected-state border color). */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
