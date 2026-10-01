export type HeaderProps = {
  productName?: string
  eyebrow?: string
}

export function Header({ productName = 'Portfolio Manager', eyebrow = 'Safe smart accounts' }: HeaderProps) {
  return (
    <header className="flex items-center justify-between border-b border-border px-8 py-5">
      <div className="flex items-center gap-3">
        <span className="flex size-7 items-center justify-center rounded-lg bg-text text-sm font-bold text-bg">
          P
        </span>
        <span className="font-semibold text-text">{productName}</span>
      </div>
      <span className="text-sm text-text-muted">{eyebrow}</span>
    </header>
  )
}
