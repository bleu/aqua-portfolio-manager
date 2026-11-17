"use client";

import { Bar, BarChart, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { formatUsd } from "@/lib/format";

export type VolumeBar = { date: string; value: number };

export type VolumeBarChartProps = {
  bars: VolumeBar[];
};

function VolumeTooltip({ active, payload }: { active?: boolean; payload?: { payload: VolumeBar }[] }) {
  if (!active || !payload?.length) return null;
  const bar = payload[0]!.payload;
  return (
    <div className="w-[200px] rounded-[20px] border border-[#2a2e33] bg-[#1d2125] px-5 py-4">
      <p className="text-sm text-[#8b9096]">{bar.date}</p>
      <p className="mt-2.5 text-[15px] font-semibold text-white">{formatUsd(bar.value)}</p>
      <p className="mt-2 text-[10px] leading-[1.4] text-[#8b9096] italic">
        The total value of trades routed through your portfolio.
      </p>
    </div>
  );
}

/** The dashboard's "Volume" tab: one bar per day, light teal, the hovered bar in full accent
 *  teal, matching the Claude Artifact's Dashboard_Volume.dc.html exactly. */
export function VolumeBarChart({ bars }: VolumeBarChartProps) {
  return (
    <div className="h-[210px] w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={bars} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
          <Tooltip content={<VolumeTooltip />} cursor={false} />
          <Bar dataKey="value" radius={[3, 3, 0, 0]} maxBarSize={6}>
            {bars.map((bar, i) => (
              <Cell key={i} fill="#dff1f3" className="hover:fill-accent" />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
