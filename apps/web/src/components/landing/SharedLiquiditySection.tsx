export function SharedLiquiditySection() {
  return (
    <section className="flex flex-col items-center gap-8 px-6 text-center">
      <img src="/landing/bubbles.svg" alt="" className="h-[110.595px] w-[40.381px]" />
      <div className="flex flex-col items-center gap-3">
        <h2 className="font-display text-[clamp(24px,1.2vw+14px,32px)] font-normal leading-[1.24] text-ink-primary">
          Built on shared liquidity
        </h2>
        <p className="font-inter max-w-[340px] text-lg leading-[1.25] text-ink-secondary">
          Powered by the infrastructure behind capital-efficient DeFi.
        </p>
        <img src="/landing/1inch-logo.png" alt="1inch" className="h-[38px] w-[94px] object-cover" />
      </div>
    </section>
  );
}
