import { Button } from "@/components/Button";
import { Decor } from "./Decor";
import { GUTTER, type LaunchProps } from "./LandingChrome";

export function ClosingSection({ onLaunch, isConnecting }: LaunchProps) {
  return (
    <section className={GUTTER}>
      <div className="relative overflow-clip rounded-[36px] bg-gradient-to-b from-[#f0f9fa] to-accent p-8 sm:p-14 lg:p-20">
        <div className="relative z-10 flex max-w-[884px] flex-col gap-8">
          <div className="flex flex-col gap-4 text-[#121518]">
            <h2 className="font-display text-[clamp(30px,2.4vw+12px,52px)] font-medium leading-[1.2]">
              Put your portfolio in{" "}
              <span className="relative inline-block">
                Trim
                <img
                  src="/landing/underline-closing.svg"
                  alt=""
                  className="pointer-events-none absolute -bottom-3 left-0 h-5 w-full max-w-none rotate-[6.37deg]"
                />
              </span>
            </h2>
            <p className="max-w-[840px] text-[clamp(18px,0.5vw+14px,24px)] leading-[1.3]">
              Set your targets, put your liquidity to work, and keep your exposure in check.
            </p>
          </div>
          <Button
            variant="secondary"
            className="h-[50px] w-[168px] bg-surface-raised text-base text-ink-primary hover:bg-[#2a2e34]"
            disabled={isConnecting}
            onClick={onLaunch}
          >
            {isConnecting ? "Connecting…" : "Launch app"}
          </Button>
        </div>
        <Decor
          src="/landing/closing-octopus.svg"
          wrapper={{ right: -293.87, top: -268.42, width: 900.238, height: 900.238 }}
          size={{ width: 679.469, height: 679.469 }}
          transform="scaleY(-1) rotate(-155.47deg)"
          className="hidden md:flex"
        />
      </div>
    </section>
  );
}
