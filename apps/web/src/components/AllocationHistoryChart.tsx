"use client";

import { Area, AreaChart, ReferenceLine, ResponsiveContainer, Tooltip, XAxis } from "recharts";

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

function ChartTooltip({ active, payload, label, series }: { active?: boolean; payload?: { dataKey: string; value: number }[]; label?: string; series: AllocationHistorySeries[] }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-[20px] border border-[#2a2e33] bg-[#1d2125] px-5 py-4">
      <p className="text-sm text-[#8b9096]">{label}</p>
      {series.map((s) => {
        const point = payload.find((p) => p.dataKey === s.id);
        if (!point) return null;
        return (
          <p key={s.id} className="mt-2.5 flex items-center gap-2 text-[15px] font-semibold text-white">
            <span className="size-2 shrink-0 rounded-full" style={{ backgroundColor: s.color }} />
            {s.name}: {point.value.toFixed(0)}%
            <span className="font-normal text-[#8b9096]">→ {s.targetPct.toFixed(0)}% target</span>
          </p>
        );
      })}
    </div>
  );
}

/** The dashboard's "Allocation history" chart: one line per basket's current share over time,
 *  a translucent gradient fill under each (Dashboard_Allocation.dc.html's own look), plus a
 *  dashed reference line at each basket's target, and a tooltip showing current vs. target. */
export function AllocationHistoryChart({ series }: AllocationHistoryChartProps) {
  const first = series[0];
  const data = (first?.points ?? []).map((point, i) => {
    const row: Record<string, string | number> = { date: point.date };
    for (const s of series) row[s.id] = s.points[i]?.pct ?? 0;
    return row;
  });

  return (
    <div className="h-[210px] w-full">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
          <defs>
            {series.map((s) => (
              <linearGradient key={s.id} id={`allocation-fill-${s.id}`} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={s.color} stopOpacity={0.22} />
                <stop offset="100%" stopColor={s.color} stopOpacity={0.02} />
              </linearGradient>
            ))}
          </defs>
          <XAxis
            dataKey="date"
            tick={{ fill: "#6b7280", fontSize: 11 }}
            axisLine={{ stroke: "#1f2937" }}
            tickLine={false}
          />
          <Tooltip content={<ChartTooltip series={series} />} />
          {series.map((s) => (
            <ReferenceLine key={`${s.id}-target`} y={s.targetPct} stroke={s.color} strokeDasharray="4 4" strokeOpacity={0.5} />
          ))}
          {series.map((s) => (
            <Area
              key={s.id}
              type="monotone"
              dataKey={s.id}
              name={s.name}
              stroke={s.color}
              strokeWidth={2}
              fill={`url(#allocation-fill-${s.id})`}
              dot={false}
            />
          ))}
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
