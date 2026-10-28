// Imported from @wagmi/connectors' own per-connector subpaths, not wagmi/connectors' barrel file
// -- that barrel re-exports every connector from one module, so bundling it used to drag in
// baseAccount's own transitive dependency chain (@coinbase/cdp-sdk) even on a page that never
// called baseAccount(), and failed `next build` outright. Importing baseAccount's own subpath
// directly (confirmed by a real build, not assumed) doesn't hit that: @base-org/account is now a
// real, explicit dependency (package.json), not an unresolved optional one the bundler chokes on.
import { baseAccount } from "@wagmi/connectors/baseAccount";
import { safe } from "@wagmi/connectors/safe";
import { walletConnect } from "@wagmi/connectors/walletConnect";
import { createConfig, http } from "wagmi";
import { base } from "wagmi/chains";

const walletConnectProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID;

/** Base mainnet only -- matches Deploy.s.sol and every address in packages/addresses/base-mainnet.json.
 *  Every connector here resolves to an account this app can actually ship a strategy from -- no
 *  generic `injected()` connector, which would connect whatever raw wallet is in the browser,
 *  possibly a plain EOA this protocol can't use at all (ADR-0011: Aqua.ship()'s own `maker` is
 *  keyed by address with no account-type check, but a PM strategy needs its wallet's own
 *  execute()-style entrypoint, which a bare EOA doesn't have). Three real ways to connect:
 *  `safe()` auto-detects and connects when this page is embedded inside Safe{Wallet} as a Safe
 *  App; `walletConnect()` covers connecting from Safe{Wallet}'s own mobile/desktop app when this
 *  page isn't embedded (only registers once a real project ID is configured --
 *  https://cloud.reown.com); `baseAccount()` connects a Coinbase/Base smart wallet directly --
 *  intentionally offered only for a PM-only wallet (no BasketScopeGuard equivalent exists for
 *  this account type, confirmed directly against CoinbaseSmartWallet.sol's source: execute()/
 *  executeBatch() call out with no hook or guard of any kind, so nothing can protect a shared
 *  wallet the way a Safe's Guard does -- see ConnectSafePage's own disclosure copy). */
export const wagmiConfig = createConfig({
  chains: [base],
  connectors: [
    safe({ unstable_getInfoTimeout: 300 }),
    ...(walletConnectProjectId ? [walletConnect({ projectId: walletConnectProjectId })] : []),
    baseAccount({ appName: "Aqua Portfolio Manager" }),
  ],
  transports: {
    [base.id]: http(),
  },
  // Defers reading persisted connection state until after hydration, so the server-rendered
  // markup (always "disconnected") matches the client's first render instead of racing it.
  ssr: true,
});
