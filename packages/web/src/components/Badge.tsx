import type { ReactNode } from 'react'
import { cn } from '../lib/cn'

export type BadgeProps = {
  children: ReactNode
  /**
   * `outline` — uppercase, bordered, tinted-background label (e.g. "SAFE SMART ACCOUNT REQUIRED").
   * `dot` — rounded pill with a leading color dot (e.g. "Aqua routing").
   */
  variant?: 'outline' | 'dot'
  className?: string
}

export function Badge({ children, variant = 'outline', className }: BadgeProps) {
  if (variant === 'dot') {
    return (
      <span
        className={cn(
          'inline-flex items-center gap-2 rounded-full bg-surface-raised px-3.5 py-1.5 text-sm font-medium text-text',
          className,
        )}
      >
        <span className="size-1.5 rounded-full bg-accent" />
        {children}
      </span>
    )
  }

  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full border border-accent-border bg-accent-soft px-3 py-1 text-xs font-semibold tracking-wide text-accent uppercase',
        className,
      )}
    >
      {children}
    </span>
  )
}
