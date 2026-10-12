// Imported from @wagmi/connectors' own per-connector subpaths, not wagmi/connectors' barrel file
// -- that barrel re-exports every connector from one module, including ones with their own
// broken transitive dependencies that this app never needed in the first place.
import { safe } from '@wagmi/connectors/safe'
import { walletConnect } from '@wagmi/connectors/walletConnect'
import { createConfig, http } from 'wagmi'
import { base } from 'wagmi/chains'

const walletConnectProjectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID as string | undefined

/** Base mainnet only -- matches Deploy.s.sol and every address in packages/addresses/base-mainnet.json.
 *  Connection is Safe-only (ADR-0011: a Safe smart account is required, not a plain EOA), so this
 *  deliberately doesn't register a generic `injected()` connector. `safe()` auto-connects when
 *  this page is embedded inside Safe{Wallet} as a Safe App; `walletConnect()` covers connecting
 *  from Safe{Wallet}'s own mobile/desktop app when this page isn't embedded (only registers once
 *  a real project ID is configured -- https://cloud.reown.com). */
export const wagmiConfig = createConfig({
  chains: [base],
  connectors: [
    safe({ unstable_getInfoTimeout: 300 }),
    ...(walletConnectProjectId ? [walletConnect({ projectId: walletConnectProjectId })] : []),
  ],
  transports: {
    [base.id]: http(),
  },
})
