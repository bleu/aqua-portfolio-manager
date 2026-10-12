import { useEffect, useRef } from 'react'
import { useAccount, useConnect } from 'wagmi'
import { Providers } from './Providers'
import { wagmiConfig } from './lib/wagmi'
import { ConnectSafePage } from './pages/ConnectSafePage'

const safeConnector = wagmiConfig.connectors.find((c) => c.type === 'safe')
const walletConnectConnector = wagmiConfig.connectors.find((c) => c.type === 'walletConnect')

/** Connection is Safe-only (ADR-0011), not a generic wallet -- see wagmi.ts's own doc comment.
 *  This scaffold has no router (BLEUDEV-397 was a single-page entry point; the full app lives on
 *  the Next.js stack built from it since, see BLEUDEV-409), so a successful connection is shown
 *  inline rather than navigated to a next page. */
function AppContent() {
  const { address, isConnected } = useAccount()
  const { connect, isPending, error } = useConnect()
  const manualConnector = walletConnectConnector ?? safeConnector

  // Auto-attempts the Safe connector once on mount, for when this page is actually embedded
  // inside Safe{Wallet} as a Safe App. A real attempt (not a separate silent one) because
  // wagmi's connector-level pending/error state is shared across hook instances targeting the
  // same connector -- two independent useConnect() calls here fought over it instead of
  // isolating cleanly.
  const attemptedAutoConnect = useRef(false)
  useEffect(() => {
    if (attemptedAutoConnect.current || !safeConnector) return
    attemptedAutoConnect.current = true
    connect({ connector: safeConnector })
    // Only ever attempted once, on mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  if (isConnected) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-bg">
        <p className="text-text">
          Connected: <span className="text-text-muted">{address}</span>
        </p>
      </div>
    )
  }

  return (
    <ConnectSafePage
      onConnectSafe={manualConnector ? () => connect({ connector: manualConnector }) : undefined}
      isConnecting={isPending}
      connectError={error?.message}
    />
  )
}

function App() {
  return (
    <Providers>
      <AppContent />
    </Providers>
  )
}

export default App
