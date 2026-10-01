import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// This script's own location pins every other path to the repo root, regardless of cwd.
const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..", "..", "..");

type Token = {
  symbol: string;
  address: string;
  feedPair: string;
  feedProxy: string;
  seedAggregator: string;
};

type Data = {
  aqua: string;
  multiSendCallOnly: string;
  maxStalenessSeconds: number;
  tokens: Token[];
};

const data: Data = JSON.parse(readFileSync(resolve(repoRoot, "packages/addresses/base-mainnet.json"), "utf8"));
const bySymbol = Object.fromEntries(data.tokens.map((t) => [t.symbol, t])) as Record<string, Token>;

function writeGenerated(path: string, content: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  console.log(`wrote ${path.replace(repoRoot + "/", "")}`);
}

// ---- 1. Solidity: packages/contracts/script/generated/BaseMainnetAddresses.sol ----

const sol = `// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @notice GENERATED FILE -- do not edit by hand.
/// @dev Regenerate from packages/addresses/base-mainnet.json: run \`pnpm generate\`
///      inside packages/addresses (BLEUDEV-398).
library BaseMainnetAddresses {
    address internal constant AQUA = ${data.aqua};
    address internal constant MULTI_SEND_CALL_ONLY = ${data.multiSendCallOnly};

    address internal constant WETH = ${bySymbol.WETH.address};
    address internal constant CBBTC = ${bySymbol.CBBTC.address};
    address internal constant USDC = ${bySymbol.USDC.address};
    address internal constant USDT = ${bySymbol.USDT.address};

    address internal constant ETH_USD_FEED = ${bySymbol.WETH.feedProxy};
    address internal constant CBBTC_USD_FEED = ${bySymbol.CBBTC.feedProxy};
    address internal constant USDC_USD_FEED = ${bySymbol.USDC.feedProxy};
    address internal constant USDT_USD_FEED = ${bySymbol.USDT.feedProxy};

    uint256 internal constant MAX_STALENESS = ${data.maxStalenessSeconds}; // ${data.maxStalenessSeconds / 3600} hours
}
`;
writeGenerated(resolve(repoRoot, "packages/contracts/script/generated/BaseMainnetAddresses.sol"), sol);

// ---- 2. TypeScript: apps/indexer/src/generated/baseMainnetAddresses.ts ----

const aggregatorEntries = [
  bySymbol.WETH,
  bySymbol.CBBTC,
  bySymbol.USDT,
  bySymbol.USDC,
]
  .map((t) => `  "${t.seedAggregator.toLowerCase()}": "${t.feedProxy.toLowerCase()}", // ${t.feedPair}`)
  .join("\n");

const ts = `// GENERATED FILE -- do not edit by hand.
// Regenerate from packages/addresses/base-mainnet.json via
// \`pnpm --filter @aqua-portfolio-manager/addresses generate\` (BLEUDEV-398).

// Each proxy's \`aggregator()\` result as of 2026-09-28 (see config.yaml's ChainlinkAggregator
// seed comment) -- covers the AnswerUpdated handler for the case where an aggregator's very
// first indexed event predates any ChainlinkAggregatorFeed row for it (nothing has ever pointed
// an AggregatorConfirmed at it yet, because it was already the live one at indexer setup).
export const SEED_AGGREGATOR_TO_PROXY: Record<string, string> = {
${aggregatorEntries}
};
`;
writeGenerated(resolve(repoRoot, "apps/indexer/src/generated/baseMainnetAddresses.ts"), ts);

// ---- 3. YAML: apps/indexer/config.yaml (static scaffolding + generated address lists) ----

const erc20Order = [bySymbol.USDC, bySymbol.USDT, bySymbol.WETH, bySymbol.CBBTC];
const erc20Comment: Record<string, string> = { USDC: "USDC", USDT: "USDT", WETH: "WETH", CBBTC: "cbBTC" };
const erc20Lines = erc20Order.map((t) => `          - "${t.address}" # ${erc20Comment[t.symbol]}`).join("\n");

const feedOrder = [bySymbol.WETH, bySymbol.CBBTC, bySymbol.USDT, bySymbol.USDC];
const feedComment: Record<string, string> = {
  WETH: "ETH/USD, WETH's feed",
  CBBTC: "cbBTC/USD, cbBTC's feed",
  USDT: "USDT/USD",
  USDC: "USDC/USD",
};
const feedLines = feedOrder.map((t) => `          - "${t.feedProxy}" # ${feedComment[t.symbol]}`).join("\n");

const aggComment: Record<string, string> = { WETH: "ETH/USD", CBBTC: "cbBTC/USD", USDT: "USDT/USD", USDC: "USDC/USD" };
const aggLines = feedOrder.map((t) => `          - "${t.seedAggregator}" # ${aggComment[t.symbol]}`).join("\n");

const yaml = `# See docs/adr/0014-production-arbitrageur-design.md for the design this implements.
#
# Indexes the real Aqua registry contract -- one deterministic address, identical across every
# chain Aqua is live on (lib/aqua/README.md's deployment table) -- not something we deploy.
name: indexer
ecosystem: evm
contracts:
  - name: Aqua
    handler: src/EventHandlers.ts
    events:
      - event: "Shipped(address maker, address app, bytes32 strategyHash, bytes strategy)"
        field_selection:
          transaction_fields:
            - hash
      # Pushed also fires on every later trade (pull/push cycle), not just at ship() time --
      # the handler tells the two apart by comparing transaction hashes against the strategy's
      # own shippedAtTxHash, not by indexing scope. Needed to learn the token universe a strategy
      # declared at ship() time: Shipped's own event args don't carry \`tokens\`/\`amounts\` (only
      # \`strategy\`, the opaque program bytes), and the maker's wallet is required to be a Safe
      # (ADR-0011), so the top-level transaction is Safe.execTransaction(...), not a direct
      # ship() call -- decoding transaction calldata directly would silently break for every
      # real PM wallet. Pushed events are emitted by Aqua.sol itself, so they're unaffected by
      # how the call arrived.
      - event: "Pushed(address maker, address app, bytes32 strategyHash, address token, uint256 amount)"
        field_selection:
          transaction_fields:
            - hash
      - event: "Docked(address maker, address app, bytes32 strategyHash)"
        field_selection:
          transaction_fields:
            - hash
  # ADR-0014's token allow list (USDC, USDT, WETH, WBTC) -- one contract definition since every
  # ERC20 shares the same Transfer event, listed once per address under \`chains\` below. The
  # handler filters to Transfers touching a known Strategy Wallet; every other Transfer on these
  # tokens (the vast majority) is indexed too and discarded in-handler, not filtered at the
  # source, since the wallet set is only known from already-indexed Strategy data.
  - name: ERC20
    handler: src/EventHandlers.ts
    events:
      - event: "Transfer(address indexed from, address indexed to, uint256 value)"
        field_selection:
          transaction_fields:
            - hash
  # ADR-0014's Oracle Price record. Each feed's well-known address (listed under ChainlinkProxy
  # below) is an \`EACAggregatorProxy\` that never emits \`AnswerUpdated\` itself -- only its current
  # underlying aggregator does, and Chainlink can swap that aggregator over time. ChainlinkProxy's
  # AggregatorConfirmed handler registers the new aggregator
  # (see EventHandlers.ts's \`contractRegister\`) so ChainlinkAggregator keeps following the live
  # one; ChainlinkAggregator itself carries no static addresses beyond its seed list below.
  - name: ChainlinkProxy
    handler: src/EventHandlers.ts
    events:
      - event: "AggregatorConfirmed(address indexed previous, address indexed latest)"
  - name: ChainlinkAggregator
    handler: src/EventHandlers.ts
    events:
      - event: "AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt)"
        field_selection:
          transaction_fields:
            - hash
chains:
  - id: 8453 # Base -- matches Deploy.s.sol's AQUA_MAINNET default already in use for local dev.
    # This Portfolio Manager Router's own deployment block on Base (packages/contracts/script/
    # Deploy.s.sol's broadcast receipt), not Aqua's -- nothing could have shipped through this
    # Router before it existed, so indexing Aqua's full history from its own 38281777 deployment
    # block wastes sync time on strategies from other apps we'll never touch. The handler doesn't
    # filter Shipped by \`app\` (see src/EventHandlers.ts), so other apps' strategies shipped after
    # this block still get indexed -- only the ones before it are skipped.
    start_block: 51925518
    contracts:
      - name: Aqua
        address:
          - "${data.aqua.toLowerCase()}"
      - name: ERC20
        # Base mainnet addresses, matching the constants PortfolioManagerMultiTokenBasketE2E.t.sol
        # already verifies against a real fork, except cbBTC replaces WBTC as the real basket's
        # BTC leg (cbBTC is the more liquid, more actively traded BTC exposure on Base).
        address:
${erc20Lines}
      - name: ChainlinkProxy
        # Base mainnet feed addresses, matching the constants PortfolioManagerMultiTokenBasketE2E.t.sol
        # already verifies against a real fork, except cbBTC/USD replaces BTC/USD (see ERC20 above).
        # All four feeds are 8-decimal, USD-quoted (verified via decimals()).
        address:
${feedLines}
      - name: ChainlinkAggregator
        # Each proxy's \`aggregator()\` result as of 2026-09-28 (see EventHandlers.ts's seed map).
        # A swap between \`start_block\` and whenever a feed's first \`AggregatorConfirmed\` lands
        # after this file's own commit is not covered: AnswerUpdated history from a
        # still-earlier aggregator than this seed is not indexed.
        # Every swap from here forward is, via ChainlinkProxy's AggregatorConfirmed handler.
        address:
${aggLines}
`;
writeGenerated(resolve(repoRoot, "apps/indexer/config.yaml"), yaml);

// ---- 4. apps/arbitrageur/.env.example: patch ALLOWED_TOKENS / ALLOWED_FEEDS in place ----

const envPath = resolve(repoRoot, "apps/arbitrageur/.env.example");
const envTokenOrder = [bySymbol.USDC, bySymbol.USDT, bySymbol.WETH, bySymbol.CBBTC];
const allowedTokens = envTokenOrder.map((t) => t.address).join(",");
const allowedFeeds = [bySymbol.USDC, bySymbol.USDT, bySymbol.WETH, bySymbol.CBBTC].map((t) => t.feedProxy).join(",");

let env = readFileSync(envPath, "utf8");
const tokenLineRe = /^ALLOWED_TOKENS=.*$/m;
const feedLineRe = /^ALLOWED_FEEDS=.*$/m;
if (!tokenLineRe.test(env) || !feedLineRe.test(env)) {
  throw new Error(`${envPath}: expected ALLOWED_TOKENS and ALLOWED_FEEDS lines, found none -- generator is stale`);
}
env = env.replace(tokenLineRe, `ALLOWED_TOKENS=${allowedTokens}`);
env = env.replace(feedLineRe, `ALLOWED_FEEDS=${allowedFeeds}`);
writeFileSync(envPath, env);
console.log(`wrote ${envPath.replace(repoRoot + "/", "")} (ALLOWED_TOKENS/ALLOWED_FEEDS lines only)`);
