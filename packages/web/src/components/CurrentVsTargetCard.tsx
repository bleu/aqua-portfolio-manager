import type { ReactNode } from 'react'
import { AllocationBar, type AllocationBarProps } from './AllocationBar'
import { Badge } from './Badge'
import { ArrowUpRightIcon, PinIcon } from './icons'
import { cn } from '../lib/cn'

export type CurrentVsTargetCardProps = {
  title?: string
  subtitle?: string
  baskets: AllocationBarProps[]
  footerNote?: string
  className?: string
}

function LegendItem({ children, swatch }: { children: ReactNode; swatch: ReactNode }) {
  return (
    <span className="inline-flex items-center gap-2 text-sm text-text-muted">
      {swatch}
      {children}
    </span>
  )
}

/**
 * Static illustration of how Aqua routing rebalances a 2-basket portfolio toward its target
 * weights — the entry page's preview of the mechanic, before a Safe is connected.
 */
export function CurrentVsTargetCard({
  title = 'Current vs. target',
  subtitle = 'How Aqua routing rebalances the portfolio',
  baskets,
  footerNote = 'Eligible routed trades earn LP fees for your portfolio.',
  className,
}: CurrentVsTargetCardProps) {
  return (
    <div className={cn('rounded-2xl border border-border bg-surface p-6', className)}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-lg font-semibold text-text">{title}</h2>
          <p className="mt-1 text-sm text-text-muted">{subtitle}</p>
        </div>
        <Badge variant="dot">Aqua routing</Badge>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-4">
        <LegendItem swatch={<span className="h-2.5 w-4 rounded-full bg-accent-muted" />}>
          Current allocation
        </LegendItem>
        <LegendItem swatch={<span className="h-2.5 w-4 rounded-full bg-accent" />}>Gap to target</LegendItem>
        <LegendItem swatch={<PinIcon className="size-2.5 text-text-muted" />}>Target</LegendItem>
      </div>

      <div className="mt-5 flex flex-col gap-4">
        {baskets.map((basket) => (
          <AllocationBar key={basket.label} {...basket} />
        ))}
      </div>

      <div className="mt-4 flex items-center gap-3 rounded-xl bg-surface-raised px-4 py-3.5">
        <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-accent-muted text-text">
          <ArrowUpRightIcon className="size-3.5" />
        </span>
        <span className="text-sm text-text">{footerNote}</span>
      </div>
    </div>
  )
}
