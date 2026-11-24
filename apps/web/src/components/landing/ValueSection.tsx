import { Decor } from "./Decor";
import { GUTTER } from "./LandingChrome";
import { AQUA_URL, DOCS_URL } from "./links";
import { LinkButton } from "./LinkButton";

const CARD =
  "relative flex min-h-[280px] flex-col justify-between gap-8 overflow-clip rounded-[20px] bg-gradient-to-b from-[#f0f9fa] to-accent p-8 text-surface-card sm:pr-24 2xl:pr-[200px]";

function CardCopy({ title, children }: { title: string; children: string }) {
  return (
    <div className="relative z-10 flex flex-col gap-4">
      <h3 className="text-[26px] font-bold leading-[1.4]">{title}</h3>
      <p className="text-base leading-normal">{children}</p>
    </div>
  );
}

export function ValueSection() {
  return (
    <section className={`flex flex-col gap-8 ${GUTTER}`}>
      <div className="flex flex-col items-start justify-between gap-6 lg:flex-row lg:items-end">
        <h2 className="font-display text-[clamp(30px,1.8vw+14px,42px)] font-normal leading-[1.24] text-ink-primary">
          Make your liquidity
          <br />
          work <span className="text-accent">smarter</span>
          <img
            src="/landing/sparkle-heading.svg"
            alt=""
            className="ml-2 inline-block h-[26px] w-[38px] max-w-none rotate-180 align-middle"
          />
        </h2>
        <p className="max-w-[365px] text-base leading-normal text-ink-primary lg:text-right">
          Built on 1inch Aqua&apos;s shared liquidity model, <span className="font-display">Trim</span> helps you maintain
          your target exposure while your capital works across DeFi.
        </p>
      </div>

      <div className="grid gap-8 md:grid-cols-2">
        <div className={CARD}>
          <Decor
            src="/landing/card-octopus-a.svg"
            wrapper={{ left: 132, top: -622, width: 1517.916, height: 1533.422 }}
            size={{ width: 1132.569, height: 1164.521 }}
            transform="scaleY(-1) rotate(-155.07deg)"
          />
          <CardCopy title="Give your capital more ways to work">
            Aqua lets the same capital support multiple strategies. Use Trim alongside other strategies without
            splitting your liquidity.
          </CardCopy>
          <LinkButton external href={AQUA_URL} className="relative z-10 self-start">
            Learn about Aqua
          </LinkButton>
        </div>

        <div className={CARD}>
          <Decor
            src="/landing/card-octopus-b.svg"
            wrapper={{ left: -378, top: -665, width: 1517.916, height: 1533.422 }}
            size={{ width: 1132.569, height: 1164.521 }}
            transform="scaleY(-1) rotate(-155.07deg)"
          />
          <Decor
            src="/landing/card-wave.svg"
            wrapper={{ left: -255, top: 49, width: 725.979, height: 472.551 }}
            size={{ width: 736.478, height: 154.25 }}
            transform="scaleY(-1) rotate(-152.93deg)"
          />
          <CardCopy title="Control your exposure">
            As your capital earns LP fees from eligible Aqua-routed trades, Trim moves your exposure toward your
            targets.
          </CardCopy>
          <LinkButton external href={DOCS_URL} className="relative z-10 self-start">
            Learn about Trim
          </LinkButton>
        </div>
      </div>
    </section>
  );
}
