import { AllocationChartCard, StatsCard } from "./MockCards";
import { Decor, Tilted } from "./Decor";
import { cn } from "@/lib/cn";

/* The four product previews of "How it works". Each one is laid out on Figma's 818 x 443 card,
 * so its coordinates are in px from the card's top-left corner. Figures are examples. */

export function BasketsPreview() {
  return (
    <>
      <Decor
        src="/landing/hero-octopus-a.svg"
        wrapper={{ left: -434, top: -525, width: 1176.207, height: 1157.725 }}
        size={{ width: 936.304, height: 962.719 }}
        transform="scaleY(-1) rotate(74.65deg)"
      />
      <Tilted
        wrapper={{ left: 364, top: 52, width: 400.99, height: 466.694 }}
        size={{ width: 334, height: 415 }}
        transform="rotate(10deg)"
        className="rounded-[20px] shadow-[4px_0px_10px_2px_rgba(0,0,0,0.25)]"
      >
        <img src="/landing/steps/baskets-add-tokens.png" alt="" className="size-full rounded-[20px] object-cover" />
      </Tilted>
      <Tilted
        wrapper={{ left: 54, top: 52, width: 401.163, height: 467.679 }}
        size={{ width: 334, height: 416 }}
        transform="rotate(-10deg)"
        className="rounded-[20px] shadow-[0px_4px_10px_2px_rgba(0,0,0,0.25)]"
      >
        <img src="/landing/steps/baskets-create.png" alt="" className="size-full rounded-[20px] object-cover" />
      </Tilted>
    </>
  );
}

export function TargetsPreview() {
  return (
    <>
      <img
        src="/landing/steps/targets-panel.png"
        alt=""
        className="absolute left-[calc(50%-0.5px)] top-[100px] h-[381px] w-[593px] -translate-x-1/2 rounded-[24px] object-cover shadow-[2px_4px_10px_2px_rgba(0,0,0,0.25)]"
      />
      <img
        src="/landing/steps/targets-stables.png"
        alt=""
        className="absolute left-[102px] top-[208px] h-[83px] w-[614px] rounded-[20px] object-cover shadow-[2px_2px_10px_1px_rgba(0,0,0,0.25)]"
      />
      <img
        src="/landing/steps/targets-majors.png"
        alt=""
        className="absolute left-[102px] top-[301px] h-[83px] w-[614px] rounded-[20px] object-cover shadow-[2px_2px_10px_1px_rgba(0,0,0,0.25)]"
      />
    </>
  );
}

type LimitCardProps = {
  title: string;
  description: string;
  options: string[];
  selected: number;
  texture: string;
};

function LimitCard({ title, description, options, selected, texture }: LimitCardProps) {
  return (
    <div
      className="relative flex w-[620px] flex-col overflow-clip rounded-[30px] p-6 shadow-[0px_4px_10px_2px_rgba(0,0,0,0.25)]"
      style={{
        backgroundColor: "#17181b",
        backgroundImage:
          "radial-gradient(circle 400px at -140px 230px, rgba(36,38,41,1) 0%, rgba(30,33,37,0.5) 50%, rgba(30,32,36,0.3) 100%)",
      }}
    >
      <div className="pointer-events-none absolute inset-0 overflow-hidden rounded-[30px]">
        <img
          src="/landing/steps/limits-card-texture.png"
          alt=""
          className="absolute h-[338.9%] max-w-none"
          style={{ width: "100%", ...(texture === "fee" ? { left: "-0.08%", top: "-0.16%" } : { left: "0.04%", top: "-22.79%" }) }}
        />
      </div>
      <div className="relative flex w-full flex-col gap-6">
        <div className="flex flex-col gap-2">
          <p className="text-base font-[510] leading-[22px] text-[#f8f8fc]">{title}</p>
          <p className="text-sm leading-[18px] tracking-[0.112px] text-ink-muted">{description}</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex gap-2">
            {options.map((option, i) => (
              <div
                key={option}
                className={cn(
                  "font-inter flex h-12 w-[63px] items-center justify-center rounded-[30px] border px-3 py-2 text-base leading-6 text-[#f5f5f5]",
                  i === selected ? "border-accent bg-surface-raised" : "border-[#292c30] bg-surface-card",
                )}
              >
                {option}
              </div>
            ))}
          </div>
          <span className="font-inter text-xs text-[#919aaa]">or</span>
          <div className="font-inter flex h-12 w-[121px] items-center justify-center gap-2 rounded-[30px] border border-[#292c30] bg-surface-card py-4 pl-4 pr-3 text-sm leading-[1.6]">
            <span className="text-white/50">Custom</span>
            <span className="w-[33px] text-right font-bold text-white">%</span>
          </div>
        </div>
      </div>
    </div>
  );
}

export function LimitsPreview() {
  return (
    <>
      <Tilted
        wrapper={{ left: 37, top: 190, width: 628.885, height: 218.193 }}
        size={{ width: 620 }}
        transform="rotate(-3deg)"
      >
        <LimitCard
          title="Fee tier"
          description="Set the fee you'll earn when trades are routed through your portfolio. Higher fees increase earnings per trade, but may attract fewer trades."
          options={["0.05%", "0.3%", "1%", "2%"]}
          selected={0}
          texture="fee"
        />
      </Tilted>
      <Tilted
        wrapper={{ left: 152, top: 36, width: 628.885, height: 218.193 }}
        size={{ width: 620 }}
        transform="rotate(3deg)"
      >
        <LimitCard
          title="Price deviation limit"
          description="Set the maximum price difference allowed for transactions to execute. A lower limit offers more protection but may delay execution."
          options={["1%", "2%", "5%", "10%"]}
          selected={0}
          texture="deviation"
        />
      </Tilted>
    </>
  );
}

export function RebalancePreview() {
  return (
    <>
      <Decor
        src="/landing/how-octopus.svg"
        wrapper={{ left: -309, top: -863, width: 1510.96, height: 1510.96 }}
        size={{ width: 1087, height: 1087 }}
        transform="scaleY(-1) rotate(34.39deg)"
      />
      <AllocationChartCard className="absolute left-[353.7px] top-[58.1px] rotate-[7.22deg]" />
      <StatsCard className="absolute left-[51px] top-[100px]" />
    </>
  );
}
