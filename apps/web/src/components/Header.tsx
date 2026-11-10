import { Button } from "@/components/Button";

export type HeaderProps = {
  productName?: string;
  onLaunchApp?: () => void;
};

export function Header({ productName = "trim", onLaunchApp }: HeaderProps) {
  return (
    // Confirmed on the real header (node 680:20947): h-[80px]/pt-[32px], no border -- the
    // previous version added a bottom border and shorter py-5 that aren't in the source.
    <header className="mx-auto flex h-[80px] max-w-[1512px] items-center justify-between px-[62px] pt-8">
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
