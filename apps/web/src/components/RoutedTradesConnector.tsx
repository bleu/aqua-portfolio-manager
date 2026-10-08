export type RoutedTradesConnectorProps = {
  /** e.g. "via Aqua" */
  caption?: string;
};

/** The arrow + "ROUTED TRADES" element between the current and target allocation columns. */
export function RoutedTradesConnector({ caption = "via Aqua" }: RoutedTradesConnectorProps) {
  return (
    <div className="flex flex-col items-center gap-2 text-center">
      <span className="text-[10px] font-semibold tracking-wider text-gray-500">ROUTED TRADES</span>
      <span className="flex h-10 w-10 items-center justify-center rounded-full bg-accent/20 text-accent">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path d="M2 8h11M9 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
      <span className="text-xs text-accent">{caption}</span>
    </div>
  );
}
