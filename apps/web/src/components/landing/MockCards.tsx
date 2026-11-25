import type { CSSProperties, ReactNode } from "react";
import { ChartLayers } from "./ChartLayers";
import { cn } from "@/lib/cn";

/* Illustrative product previews for the landing page. Every figure here is example data, not
 * live or historical performance, so the cards are hidden from assistive technology. */

const CARD =
  "relative flex flex-col overflow-clip rounded-[30px] border border-[#292c30] p-6 shadow-[2px_4px_10px_3px_rgba(0,0,0,0.25)]";

// Figma's radial glow in the bottom-left corner of the dark cards.
const GLOW =
  "radial-gradient(circle 600px at -100px 440px, rgba(36,38,41,1) 0%, rgba(30,33,37,0.5) 50%, rgba(30,32,36,0.3) 100%)";

const money = "font-inter font-semibold text-[#f1f4fa]";

function PeriodChip() {
  return (
    <div className="flex items-center justify-center rounded-lg border border-[#f0f9fa] bg-[#35484f] px-2.5 py-[7px]">
      <span className="font-inter text-[11px] font-semibold text-[#f1f4fa]">30d</span>
    </div>
  );
}

function LegendItem({ children, dot }: { children: ReactNode; dot?: "stable" | "majors" | "target" }) {
  return (
    <div className="flex items-center gap-[7px]">
      {dot === "target" ? (
        <span className="h-px w-[18px] border border-dashed border-[#919aaa] opacity-70" />
      ) : (
        <img src={`/landing/dot-${dot}.svg`} alt="" className="size-2" />
      )}
      <span className="font-inter whitespace-nowrap text-[11px] font-medium text-[#919aaa]">{children}</span>
    </div>
  );
}

/** Hero: "Managed portfolio" card with the allocation chart. */
export function HeroPortfolioCard({ className, style }: { className?: string; style?: CSSProperties }) {
  return (
    <div aria-hidden="true" className={cn(CARD, "w-[503.673px] bg-[#17181b]", className)} style={style}>
      <div className="flex w-full flex-col gap-5">
        <div className="flex items-start justify-between">
          <div className="flex flex-col gap-[5px]">
            <p className="text-[15px] leading-5 text-ink-primary">Managed portfolio</p>
            <p className={cn(money, "text-[32px]")}>$400,000.00</p>
          </div>
          <PeriodChip />
        </div>
        <div className="flex flex-wrap items-center gap-x-[18px] gap-y-2">
          <LegendItem dot="stable">Stablecoins </LegendItem>
          <LegendItem dot="majors"> Majors</LegendItem>
          <LegendItem dot="target">Target</LegendItem>
        </div>
        <ChartLayers set={1} height={137.392} />
        <div className="flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <p className="text-[15px] leading-5 text-ink-primary">Net LP fees earned</p>
            <p className={cn(money, "text-base")}>$128.42</p>
          </div>
          <div className="flex items-center justify-between">
            <p className="text-[15px] leading-5 text-ink-primary">Routed volume</p>
            <p className={cn(money, "text-base")}>$42,830</p>
          </div>
        </div>
      </div>
    </div>
  );
}

function BasketRow({
  ring,
  name,
  tokens,
  pct,
  usd,
}: {
  ring: "stable" | "majors";
  name: string;
  tokens: string[];
  pct: string;
  usd: string;
}) {
  return (
    <div className="flex h-[92px] w-full items-center justify-between rounded-[30px] bg-gradient-to-r from-white/[0.02] to-white/[0.04] p-5">
      <div className="flex items-center gap-3">
        <div className="size-[47px] flex-none rotate-90">
          <img src={`/landing/ring-${ring}.svg`} alt="" className="block size-full max-w-none" />
        </div>
        <div className="flex flex-col gap-2 pr-[82px]">
          <p className="whitespace-nowrap text-[21px] font-semibold leading-[26px] tracking-[0.168px] text-ink-primary [font-family:ui-rounded,'SF_Pro_Rounded',system-ui,sans-serif]">
            {name}
          </p>
          <p className="flex gap-1 whitespace-nowrap text-sm leading-[18px] tracking-[0.112px] text-ink-secondary">
            {tokens.map((token, i) => (
              <span key={token} className="flex gap-1">
                {i > 0 && <span>·</span>}
                {token}
              </span>
            ))}
          </p>
        </div>
      </div>
      <div className="flex w-11 flex-col items-end justify-center whitespace-nowrap">
        <p className="font-inter text-base font-medium leading-[1.6] text-[#f8fffe]">{pct}</p>
        <p className="font-inter text-xs leading-[1.6] text-[#a3a3a3]">{usd}</p>
      </div>
    </div>
  );
}

/** Hero: "Target allocation" card, 70/30 example from the Product Handoff. */
export function HeroTargetCard({ className, style }: { className?: string; style?: CSSProperties }) {
  return (
    <div aria-hidden="true" className={cn(CARD, "w-[465.25px] gap-5 bg-[#17181b]", className)} style={style}>
      <p className="text-[15px] leading-5 text-ink-primary">Target allocation</p>
      <div className="flex flex-col gap-5">
        <BasketRow ring="stable" name="Stablecoins" tokens={["USDC", "USDT", "DAI"]} pct="70%" usd="$ 280,000.0" />
        <BasketRow ring="majors" name="Majors" tokens={["BTC", "ETH"]} pct="30%" usd="$ 120,000.0" />
      </div>
    </div>
  );
}

const DARK_WITH_GLOW = { backgroundColor: "#0d0e10", backgroundImage: GLOW } satisfies CSSProperties;

/** "How it works": the summary stats card. */
export function StatsCard({ className, style }: { className?: string; style?: CSSProperties }) {
  return (
    <div
      aria-hidden="true"
      className={cn(CARD, "h-[307px] w-[324px] justify-center", className)}
      style={{ ...DARK_WITH_GLOW, ...style }}
    >
      <div className="flex min-h-px w-full flex-1 flex-col items-start justify-between">
        <div className="flex w-full items-start justify-between">
          <div className="flex flex-col gap-[5px]">
            <p className="text-[15px] leading-5 text-ink-primary">Total managed value</p>
            <p className={cn(money, "text-[32px]")}>$400,000.00</p>
          </div>
          <PeriodChip />
        </div>
        <div className="h-px w-full bg-[#272f3a] opacity-65" />
        <div className="flex h-[54px] w-full items-center justify-between">
          <div className="flex flex-col gap-1">
            <p className="text-[15px] leading-5 text-ink-primary">Net LP fees earned</p>
            <p className="text-[11px] font-[510] leading-[14px] tracking-[0.088px] text-ink-muted">After protocol fee</p>
          </div>
          <p className="font-inter text-xl font-semibold text-accent">$750</p>
        </div>
        <div className="h-px w-full bg-[#272f3a] opacity-65" />
        <div className="flex h-11 w-full items-center justify-between">
          <div className="flex flex-col gap-1">
            <p className="text-[15px] leading-5 text-ink-primary">Routed volume</p>
            <p className="text-[11px] font-[510] leading-[14px] tracking-[0.088px] text-ink-muted">212 transactions</p>
          </div>
          <p className={cn(money, "text-base")}>$2,000,000</p>
        </div>
      </div>
    </div>
  );
}

/** "How it works": the allocation chart card. */
export function AllocationChartCard({ className, style }: { className?: string; style?: CSSProperties }) {
  return (
    <div
      aria-hidden="true"
      className={cn(CARD, "w-[403px] items-center justify-center gap-8 py-6", className)}
      style={{ ...DARK_WITH_GLOW, ...style }}
    >
      <div className="flex items-center gap-[18px] px-6">
        <LegendItem dot="stable">Stablecoins current</LegendItem>
        <LegendItem dot="majors">Crypto majors current</LegendItem>
        <LegendItem dot="target">Target</LegendItem>
      </div>
      <div className="flex w-full flex-col gap-3">
        <ChartLayers set={2} height={190} />
        <div className="flex w-full justify-between px-6 font-inter text-[10px] text-[#919aaa]">
          {["Aug 25", "Sep 1", "Sep 8", "Sep 15", "Sep 24"].map((d) => (
            <span key={d}>{d}</span>
          ))}
        </div>
      </div>
    </div>
  );
}
