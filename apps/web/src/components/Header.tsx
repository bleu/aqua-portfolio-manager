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
        {/* Mint, matching the octopus mark -- the brand guide calls Mint "signature and key
            actions" and titles its logo chapter "The signature," i.e. the icon+wordmark lockup
            itself. Not yet re-confirmed against the wordmark's own node directly (Figma's MCP
            rate limit was hit before that call completed). */}
        <span className="font-display font-medium text-accent">{productName}</span>
      </div>
      <Button variant="accent" onClick={onLaunchApp}>
        Launch app
      </Button>
    </header>
  );
}
