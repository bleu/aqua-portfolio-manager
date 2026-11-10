import { Button } from "@/components/Button";

export type HeaderProps = {
  productName?: string;
  onLaunchApp?: () => void;
};

export function Header({ productName = "trim", onLaunchApp }: HeaderProps) {
  return (
    <header className="flex items-center justify-between border-b border-border px-8 py-5">
      <div className="flex items-center gap-2">
        <img src="/octopus.svg" alt="" className="size-6" />
        <span className="font-display font-medium text-ink-primary">{productName}</span>
      </div>
      <Button variant="accent" onClick={onLaunchApp}>
        Launch app
      </Button>
    </header>
  );
}
