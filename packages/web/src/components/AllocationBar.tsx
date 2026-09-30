import { ArrowLeftIcon, ArrowRightIcon, PinIcon } from './icons'
import { cn } from '../lib/cn'

export type AllocationBarProps = {
  /** Basket name, e.g. "Crypto majors". */
  label: string
  /** Current allocation, as a percent of the whole portfolio (0-100). */
  currentPct: number
  /** Target allocation, as a percent of the whole portfolio (0-100). */
  targetPct: number
  /** Short sentence explaining which way routing moves this basket. */
  caption: string
  className?: string
}

function formatPct(value: number): string {
  return `${Number(value.toFixed(1))}%`
}

/**
 * One basket's current-vs-target row: a filled bar up to the lower of the two values, a
 * highlighted "gap to target" segment spanning the difference (carrying a directional arrow),
 * and a pin marking the target position — whichever edge of the gap segment it falls on.
 */
export function AllocationBar({ label, currentPct, targetPct, caption, className }: AllocationBarProps) {
  const lower = Math.min(currentPct, targetPct)
  const upper = Math.max(currentPct, targetPct)
  const gapWidth = upper - lower
  const isShrinking = targetPct < currentPct

  return (
    <div className={cn('rounded-xl border border-border p-5', className)}>
      <div className="flex items-baseline justify-between gap-4">
        <span className="font-semibold text-text">{label}</span>
        <span className="text-sm text-text-muted">
          Current {formatPct(currentPct)} · Target {formatPct(targetPct)}
        </span>
      </div>

      <div className="relative mt-4 pt-3">
        <div className="flex h-10 overflow-hidden rounded-lg border border-border bg-bg">
          <div className="bg-accent-muted" style={{ width: `${lower}%` }} />
          {gapWidth > 0 && (
            <div
              className="flex items-center justify-center bg-accent text-text"
              style={{ width: `${gapWidth}%` }}
            >
              {isShrinking ? <ArrowLeftIcon className="size-4" /> : <ArrowRightIcon className="size-4" />}
            </div>
          )}
        </div>
        <div
          className="absolute top-0 flex -translate-x-1/2 flex-col items-center"
          style={{ left: `${targetPct}%` }}
        >
          <PinIcon className="size-3 text-text" />
          <div className="h-10 w-px bg-text/70" />
        </div>
      </div>

      <div className="mt-3 flex items-center gap-2 text-sm text-text-muted">
        <span className="size-1.5 shrink-0 rounded-full bg-accent" />
        {caption}
      </div>
    </div>
  )
}
