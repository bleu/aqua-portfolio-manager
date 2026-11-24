import type { CSSProperties } from "react";

type Layer = {
  file: string;
  /** Figma insets as percentages of the chart box: top, bottom. Left and right are always 0. */
  top: number;
  bottom: number;
  /** Figma overflow of the inner wrapper (CSS inset shorthand), when the vector bleeds out. */
  bleed?: string;
  /** Draws the vector straight into the box, without a bleed wrapper. */
  flush?: boolean;
};

const GRID: Layer[] = [5.26, 27.63, 50, 72.37, 94.74].map((top) => ({
  file: "grid",
  top,
  bottom: 100 - top,
  bleed: "-0.5px 0",
}));

function layersFor(set: 1 | 2): Layer[] {
  const lineBleed =
    set === 1
      ? { a: "-20.42% -0.33% -20.4% -0.33%", b: "-20.4% -0.33% -20.42% -0.33%" }
      : { a: "-14.77% -0.37% -14.74% -0.37%", b: "-14.74% -0.37% -14.77% -0.37%" };
  return [
    ...GRID,
    { file: "target-a", top: 35.26, bottom: 64.74, bleed: "-0.75px 0" },
    { file: "target-b", top: 64.74, bottom: 35.26, bleed: "-0.75px 0" },
    { file: "area-a", top: 34.07, bottom: 5.26, flush: true },
    { file: "area-b", top: 60.58, bottom: 5.26, flush: true },
    { file: "line-a", top: 34.07, bottom: 60.58, bleed: lineBleed.a },
    { file: "line-b", top: 60.58, bottom: 34.07, bleed: lineBleed.b },
  ];
}

export type ChartLayersProps = {
  /** 1 = the hero card's chart, 2 = the "how it works" card's chart (different line bleed). */
  set: 1 | 2;
  height: number;
};

/** The mock allocation chart, assembled from Figma's exported vector layers. Purely illustrative. */
export function ChartLayers({ set, height }: ChartLayersProps) {
  return (
    <div aria-hidden="true" className="relative w-full overflow-clip" style={{ height }}>
      {layersFor(set).map((layer, i) => {
        const box: CSSProperties = { top: `${layer.top}%`, bottom: `${layer.bottom}%`, left: 0, right: 0 };
        const src = `/landing/chart${set}-${layer.file}.svg`;
        return (
          <div key={i} className="absolute" style={box}>
            {layer.flush ? (
              <img src={src} alt="" className="absolute inset-0 block size-full max-w-none" />
            ) : (
              <div className="absolute" style={{ inset: layer.bleed }}>
                <img src={src} alt="" className="block size-full max-w-none" />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
