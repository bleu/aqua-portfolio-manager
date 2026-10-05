import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { AQUA, TOKENS } from "../src/index.js";

// config.yaml and .env.example stay hand-maintained -- this only checks that every address
// base-mainnet.json knows about still appears somewhere in each file, catching drift without
// owning their structure.
const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..", "..", "..");

const expectedAddresses = [
  AQUA,
  ...TOKENS.flatMap((t) => [t.address, t.feedProxy, t.seedAggregator]),
].map((a) => a.toLowerCase());

function checkFile(relPath: string): string[] {
  const content = readFileSync(resolve(repoRoot, relPath), "utf8").toLowerCase();
  return expectedAddresses.filter((addr) => !content.includes(addr));
}

let failed = false;
for (const [relPath, expectAll] of [
  ["apps/indexer/config.yaml", true],
  ["apps/arbitrageur/.env.example", false], // only the 4 token/feed addresses, not AQUA/aggregators
] as const) {
  const missing = checkFile(relPath).filter((addr) =>
    expectAll ? true : TOKENS.some((t) => t.address.toLowerCase() === addr || t.feedProxy.toLowerCase() === addr),
  );
  if (missing.length > 0) {
    failed = true;
    console.error(`${relPath}: missing or stale address(es): ${missing.join(", ")}`);
  }
}

if (failed) {
  console.error("\nSome address in packages/addresses/base-mainnet.json isn't reflected in the file(s) above.");
  console.error("Update the file by hand to match, or update base-mainnet.json if the source itself is stale.");
  process.exit(1);
}
console.log("config.yaml and .env.example match packages/addresses/base-mainnet.json.");
