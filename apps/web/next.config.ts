import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  outputFileTracingRoot: path.join(import.meta.dirname, "../.."),
  webpack: (config) => {
    // @wagmi/connectors' baseAccount() connector pulls in @base-org/account, whose *server*
    // (Node export condition) build includes a Pay/subscription feature this app never calls
    // (this connector is only ever used for getProvider()'s basic eth_requestAccounts flow).
    // That feature imports @coinbase/cdp-sdk, which in turn imports several @x402/* packages
    // that aren't resolvable at all (confirmed: a real `next build` fails on them outright,
    // "Module not found"). Stubbing @coinbase/cdp-sdk to an empty module is safe specifically
    // because nothing in this app's own code calls the payment/subscription path that needs it
    // -- if that ever changes, this alias needs to go, not stay.
    config.resolve.alias = { ...config.resolve.alias, "@coinbase/cdp-sdk": false };
    return config;
  },
};

export default nextConfig;
