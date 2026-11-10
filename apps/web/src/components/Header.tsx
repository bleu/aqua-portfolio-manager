import { Button } from "@/components/Button";

export type HeaderProps = {
  productName?: string;
  onLaunchApp?: () => void;
};

export function Header({ productName = "trim", onLaunchApp }: HeaderProps) {
  return (
    <header className="flex items-center justify-between border-b border-border px-8 py-5">
      <div className="flex items-center gap-2">
        <img src="/octopus.svg" alt="" className="h-[30px] w-9" />
        {/* Confirmed directly on the real landing page's header (node 680:20947): Unbounded
            Regular (not Medium), 32px, var(--highlight-mint-primary, #94cad1). */}
        <span className="font-display text-[32px] font-normal text-accent">{productName}</span>
      </div>
      <Button variant="accent" onClick={onLaunchApp}>
        Launch app
      </Button>
    </header>
  );
}
