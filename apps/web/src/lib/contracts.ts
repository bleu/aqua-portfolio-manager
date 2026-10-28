import type { Address } from "viem";

/** Fails loudly at first use instead of letting `undefined` silently flow into a contract call.
 *  Thrown, not asserted, since this runs in browser code too -- a dev-only assert would get
 *  stripped from a production build.
 *  @dev Each call site below must pass `process.env.NEXT_PUBLIC_*` as a static literal, not a
 *       variable -- Next.js only inlines `NEXT_PUBLIC_*` vars into the client bundle when it can
 *       statically see the exact `process.env.THE_NAME` expression at build time. A helper that
 *       took the var name as a string and did `process.env[name]` would silently resolve to
 *       undefined in the browser, since nothing would get inlined. */
function requiredAddress(name: string, value: string | undefined): Address {
  if (!value) {
    throw new Error(`Missing required env var ${name} -- see apps/web/.env.example.`);
  }
  return value as Address;
}

/** Portfolio Manager contract addresses, deployed to Base mainnet by
 *  packages/contracts/script/Deploy.s.sol. Never hardcode these elsewhere -- redeploying the
 *  protocol pieces means updating the four NEXT_PUBLIC_PM_* env vars, not source. */
export const PM_ROUTER_ADDRESS = requiredAddress(
  "NEXT_PUBLIC_PM_ROUTER_ADDRESS",
  process.env.NEXT_PUBLIC_PM_ROUTER_ADDRESS,
);
export const PM_TOKEN_REGISTRY_ADDRESS = requiredAddress(
  "NEXT_PUBLIC_PM_TOKEN_REGISTRY_ADDRESS",
  process.env.NEXT_PUBLIC_PM_TOKEN_REGISTRY_ADDRESS,
);
export const PM_FEED_REGISTRY_ADDRESS = requiredAddress(
  "NEXT_PUBLIC_PM_FEED_REGISTRY_ADDRESS",
  process.env.NEXT_PUBLIC_PM_FEED_REGISTRY_ADDRESS,
);
export const PM_STRATEGY_VALIDATOR_ADDRESS = requiredAddress(
  "NEXT_PUBLIC_PM_STRATEGY_VALIDATOR_ADDRESS",
  process.env.NEXT_PUBLIC_PM_STRATEGY_VALIDATOR_ADDRESS,
);
/** The shared, external Aqua registry this deployment's Router/Validator were built against
 *  (packages/addresses/base-mainnet.json's "aqua" field) -- not something this repo deploys or
 *  redeploys, but still env-driven rather than hardcoded in case Aqua itself is ever upgraded. */
export const AQUA_ADDRESS = requiredAddress("NEXT_PUBLIC_AQUA_ADDRESS", process.env.NEXT_PUBLIC_AQUA_ADDRESS);

/** Deliberately optional, unlike every address above: set only once
 *  packages/contracts/script/DeployBasketScopeGuardFactory.s.sol has actually been run against
 *  Base mainnet. Left unset, the ship wizard's Guard-deploy/install steps are skipped entirely
 *  (see buildShipSteps in safeProposal.ts) -- the rest of the app must keep working before that
 *  one-time deployment happens, so this can't use requiredAddress. */
export const PM_BASKET_SCOPE_GUARD_FACTORY_ADDRESS = process.env.NEXT_PUBLIC_PM_BASKET_SCOPE_GUARD_FACTORY_ADDRESS as
  | Address
  | undefined;
