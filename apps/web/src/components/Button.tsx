import type { ButtonHTMLAttributes } from 'react'
import { cn } from '../lib/cn'

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'secondary'
}

export function Button({ variant = 'primary', className, ...props }: ButtonProps) {
  return (
    <button
      className={cn(
        'inline-flex items-center justify-center rounded-[10px] px-6 py-3 text-base font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-not-allowed disabled:opacity-50',
        variant === 'primary' &&
          'bg-text text-bg hover:bg-white active:bg-text-muted',
        variant === 'secondary' &&
          'border border-border-strong bg-transparent text-text hover:bg-surface-raised',
        className,
      )}
      {...props}
    />
  )
}
