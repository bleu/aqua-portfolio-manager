export type HeaderProps = {
  productName?: string;
  eyebrow?: string;
};

export function Header({ productName = "Portfolio Manager", eyebrow = "Safe smart accounts" }: HeaderProps) {
  return (
    <header className="flex items-center justify-between border-b border-border px-8 py-5">
      <div className="flex items-center gap-3">
        <span className="flex size-7 items-center justify-center rounded-lg bg-white text-sm font-bold text-surface">
          P
        </span>
        <span className="font-semibold text-white">{productName}</span>
      </div>
      <span className="text-sm text-gray-400">{eyebrow}</span>
    </header>
  );
}
