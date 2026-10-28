// Imported from @wagmi/connectors' own per-connector subpaths, not wagmi/connectors' barrel file
// -- that barrel re-exports every connector from one module, so bundling it drags in
// baseAccount's own transitive dependency chain (@coinbase/cdp-sdk) even though nothing here
// calls baseAccount(). That chain currently has a broken import of its own and fails
// `next build` outright; this app never needed it in the first place.
import { safe } from "@wagmi/connectors/safe";
import { walletConnect } from "@wagmi/connectors/walletConnect";
import { createConfig, http } from "wagmi";
import { base } from "wagmi/chains";

const walletConnectProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID;

/** Base mainnet only -- matches Deploy.s.sol and every address in packages/addresses/base-mainnet.json.
 *  Connection is Safe-only (ADR-0011: a Safe smart account is required, not a plain EOA), so this
 *  deliberately doesn't register a generic `injected()` connector -- that would connect whatever
 *  raw wallet is in the browser, which may not even be a Safe. Two real ways to connect a Safe:
 *  `safe()` auto-detects and connects when this page is embedded inside Safe{Wallet} as a Safe
 *  App; `walletConnect()` covers connecting from Safe{Wallet}'s own mobile/desktop app when this
 *  page isn't embedded (only registers once a real project ID is configured --
 *  https://cloud.reown.com). */
export const wagmiConfig = createConfig({
  chains: [base],
  connectors: [
    safe({ unstable_getInfoTimeout: 300 }),
    ...(walletConnectProjectId ? [walletConnect({ projectId: walletConnectProjectId })] : []),
  ],
  transports: {
    [base.id]: http(),
  },
  // Defers reading persisted connection state until after hydration, so the server-rendered
  // markup (always "disconnected") matches the client's first render instead of racing it.
  ssr: true,
});
