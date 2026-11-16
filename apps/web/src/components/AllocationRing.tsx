export type AllocationRingProps = {
  /** 0-100 */
  percentage: number;
  color: string;
  size?: number;
  className?: string;
};

/** The small per-basket progress ring in the Targets table (node 680:20784/680:20810,
 *  "Baskets" panel of the "2. Targets" flow screen): a colored arc over a muted track, sized to
 *  the basket's share. Figma's own asset there is a pre-baked 35%/65% vector pair, not something
 *  that generalizes to an arbitrary user-set target -- this draws the same shape as a real SVG
 *  arc instead, parameterized by `percentage`. */
export function AllocationRing({ percentage, color, size = 40, className }: AllocationRingProps) {
  const strokeWidth = size * 0.17;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const clamped = Math.min(100, Math.max(0, percentage));
  const dash = (clamped / 100) * circumference;

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className={className} aria-hidden="true">
      <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke="currentColor" className="text-white/10" strokeWidth={strokeWidth} />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={radius}
        fill="none"
        stroke={color}
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeDasharray={`${dash} ${circumference - dash}`}
        transform={`rotate(-90 ${size / 2} ${size / 2})`}
      />
    </svg>
  );
}
