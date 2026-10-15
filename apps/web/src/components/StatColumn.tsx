export type StatColumnProps = {
  value: string;
  label: string;
};

/** One column of the activated page's 4-across stat row: a large number over a small caption.
 *  Distinct from the Portfolio overview card's stacked MetricRow (label-above-value-above-
 *  caption, with dividers) -- different pages, different shapes, don't conflate the two. */
export function StatColumn({ value, label }: StatColumnProps) {
  return (
    <div className="text-center">
      <p className="text-2xl font-bold text-white">{value}</p>
      <p className="mt-0.5 text-xs text-gray-500">{label}</p>
    </div>
  );
}
