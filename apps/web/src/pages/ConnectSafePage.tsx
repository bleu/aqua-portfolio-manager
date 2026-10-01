import { Badge } from '../components/Badge'
import { Button } from '../components/Button'
import { CurrentVsTargetCard } from '../components/CurrentVsTargetCard'
import { Header } from '../components/Header'

export type ConnectSafePageProps = {
  onConnectSafe?: () => void
}

/** V1 entry/onboarding, "01 · Connect Safe": the Safe-connection landing page (BLEUDEV-397). */
export function ConnectSafePage({ onConnectSafe }: ConnectSafePageProps) {
  return (
    <div className="min-h-screen bg-bg">
      <Header />

      <main className="mx-auto grid max-w-6xl gap-12 px-8 py-20 lg:grid-cols-2 lg:items-center">
        <div>
          <Badge variant="outline">Safe smart account required</Badge>

          <h1 className="mt-6 text-5xl leading-[1.05] font-bold text-text">
            Keep your portfolio on target
          </h1>

          <p className="mt-6 max-w-md text-base leading-relaxed text-text-muted">
            Connect a Safe, choose the tokens to manage, and set a target for each group. Trades
            routed through Aqua help maintain those targets while your portfolio earns LP fees.
          </p>

          <Button className="mt-8" onClick={onConnectSafe}>
            Connect Safe
          </Button>

          <p className="mt-4 text-sm text-text-faint">
            You can connect with WalletConnect or open Portfolio Manager as a Safe App.
          </p>
        </div>

        <CurrentVsTargetCard
          baskets={[
            {
              label: 'Crypto majors',
              currentPct: 42,
              targetPct: 33.3,
              caption: 'Routing reduces the overweight basket toward 33.3%',
            },
            {
              label: 'Stablecoins',
              currentPct: 58,
              targetPct: 66.7,
              caption: 'Routing increases the underweight basket toward 66.7%',
            },
          ]}
        />
      </main>
    </div>
  )
}
