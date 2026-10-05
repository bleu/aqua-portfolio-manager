import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { AQUA, MULTI_SEND_CALL_ONLY, MAX_STALENESS_SECONDS, TOKENS } from "../src/index.js";

// This script's own location pins the output path to the repo root, regardless of cwd.
const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..", "..", "..");

const bySymbol = Object.fromEntries(TOKENS.map((t) => [t.symbol, t]));

const sol = `// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @notice GENERATED FILE -- do not edit by hand.
/// @dev Regenerate from packages/addresses/src/index.ts: run \`pnpm generate-solidity\`
///      inside packages/addresses.
library BaseMainnetAddresses {
    address internal constant AQUA = ${AQUA};
    address internal constant MULTI_SEND_CALL_ONLY = ${MULTI_SEND_CALL_ONLY};

    address internal constant WETH = ${bySymbol.WETH.address};
    address internal constant CBBTC = ${bySymbol.CBBTC.address};
    address internal constant USDC = ${bySymbol.USDC.address};
    address internal constant USDT = ${bySymbol.USDT.address};

    address internal constant ETH_USD_FEED = ${bySymbol.WETH.feedProxy};
    address internal constant CBBTC_USD_FEED = ${bySymbol.CBBTC.feedProxy};
    address internal constant USDC_USD_FEED = ${bySymbol.USDC.feedProxy};
    address internal constant USDT_USD_FEED = ${bySymbol.USDT.feedProxy};

    uint256 internal constant MAX_STALENESS = ${MAX_STALENESS_SECONDS}; // ${MAX_STALENESS_SECONDS / 3600} hours
}
`;

const outPath = resolve(repoRoot, "packages/contracts/script/generated/BaseMainnetAddresses.sol");
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, sol);
console.log(`wrote ${outPath.replace(repoRoot + "/", "")}`);
