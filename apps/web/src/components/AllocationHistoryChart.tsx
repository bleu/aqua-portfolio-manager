"use client";

import { Line, LineChart, ReferenceLine, ResponsiveContainer, XAxis } from "recharts";

export type AllocationHistorySeries = {
  id: string;
  name: string;
  color: string;
  /** The basket's fixed target share, drawn as a dashed reference line. */
  targetPct: number;
  /** Current-allocation share (0-100) at each point, assumed aligned across every series by index. */
  points: { date: string; pct: number }[];
};

export type AllocationHistoryChartProps = {
  series: AllocationHistorySeries[];
};

/** The dashboard's "Allocation history" chart: one line per basket's current share over time,
 *  plus a dashed reference line at each basket's target. The one genuinely new piece of chart
 *  infrastructure in this app -- uses recharts rather than hand-rolled SVG path math. */
export function AllocationHistoryChart({ series }: AllocationHistoryChartProps) {
  const first = series[0];
  const data = (first?.points ?? []).map((point, i) => {
    const row: Record<string, string | number> = { date: point.date };
    for (const s of series) row[s.id] = s.points[i]?.pct ?? 0;
    return row;
  });

  return (
    <div className="h-64 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
          <XAxis
            dataKey="date"
            tick={{ fill: "#6b7280", fontSize: 11 }}
            axisLine={{ stroke: "#1f2937" }}
            tickLine={false}
          />
          {series.map((s) => (
            <ReferenceLine key={`${s.id}-target`} y={s.targetPct} stroke={s.color} strokeDasharray="4 4" strokeOpacity={0.5} />
          ))}
          {series.map((s) => (
            <Line
              key={s.id}
              type="monotone"
              dataKey={s.id}
              name={s.name}
              stroke={s.color}
              strokeWidth={2}
              dot={false}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
