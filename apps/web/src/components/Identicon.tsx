import { identiconFor } from "@/lib/identicon";

export type IdenticonProps = {
  address: string;
  size?: number;
  className?: string;
};

/** Renders the deterministic per-address identicon from lib/identicon.ts as inline SVG. */
export function Identicon({ address, size = 24, className }: IdenticonProps) {
  const { cells, background, foreground } = identiconFor(address);
  const cellSize = size / 5;

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className={className} aria-hidden="true">
      <rect width={size} height={size} fill={background} rx={size * 0.33} />
      {cells.map((row, rowIndex) =>
        row.map(
          (filled, colIndex) =>
            filled && (
              <rect
                key={`${rowIndex}-${colIndex}`}
                x={colIndex * cellSize}
                y={rowIndex * cellSize}
                width={cellSize}
                height={cellSize}
                fill={foreground}
              />
            ),
        ),
      )}
    </svg>
  );
}
