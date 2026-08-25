#!/usr/bin/env node
/**
 * CLI: run the pre-existing-strategy check before installing BasketScopeGuard on a
 * candidate Safe.
 *
 * Usage:
 *   pnpm cli --rpc <url> --aqua <address> --maker <address> \
 *     --trusted-strategy-hash <bytes32> --groups <path/to/groups.json> \
 *     [--from-block <n>] [--to-block <n|latest>]
 *
 * groups.json shape: { "<tokenAddress>": "<groupId>", ... } -- see README.md for a
 * worked example.
 */

import { readFileSync } from "node:fs";
import { createPublicClient, http, isAddress, isHex } from "viem";
import { checkOnboarding, type GroupConfig } from "./scan.js";

function parseArgs(argv: string[]): Record<string, string> {
  const args: Record<string, string> = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    if (!key?.startsWith("--")) throw new Error(`expected a --flag, got "${key}"`);
    const value = argv[i + 1];
    if (value === undefined) throw new Error(`missing value for ${key}`);
    args[key.slice(2)] = value;
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const rpc = args["rpc"];
  const aqua = args["aqua"];
  const maker = args["maker"];
  const trustedStrategyHash = args["trusted-strategy-hash"];
  const groupsPath = args["groups"];

  if (!rpc || !aqua || !maker || !trustedStrategyHash || !groupsPath) {
    console.error(
      "Usage: cli --rpc <url> --aqua <address> --maker <address> --trusted-strategy-hash <bytes32> --groups <path> [--from-block <n>] [--to-block <n|latest>]",
    );
    process.exit(2);
  }
  if (!isAddress(aqua)) throw new Error(`--aqua is not a valid address: ${aqua}`);
  if (!isAddress(maker)) throw new Error(`--maker is not a valid address: ${maker}`);
  if (!isHex(trustedStrategyHash) || trustedStrategyHash.length !== 66) {
    throw new Error(`--trusted-strategy-hash must be a 32-byte hex value: ${trustedStrategyHash}`);
  }

  const rawGroups = JSON.parse(readFileSync(groupsPath, "utf8")) as Record<string, string>;
  const groupConfig: GroupConfig = {};
  for (const [token, group] of Object.entries(rawGroups)) {
    if (!isAddress(token)) throw new Error(`groups.json has an invalid token address: ${token}`);
    groupConfig[token.toLowerCase()] = group;
  }

  const client = createPublicClient({ transport: http(rpc) });
  const fromBlock = args["from-block"] ? BigInt(args["from-block"]) : 0n;
  const toBlock = args["to-block"] && args["to-block"] !== "latest" ? BigInt(args["to-block"]) : await client.getBlockNumber();

  const result = await checkOnboarding(client, aqua, maker, groupConfig, trustedStrategyHash, fromBlock, toBlock);

  console.log(`Scanned maker ${result.maker}: ${result.strategiesFound} pre-existing strategy(ies) found.`);
  if (result.compliant) {
    console.log("OK -- no group-boundary violations. Safe to install BasketScopeGuard on this Safe.");
    process.exit(0);
  }

  console.error(`REFUSED -- ${result.violations.length} violation(s) found:`);
  for (const v of result.violations) {
    console.error(`  - strategy ${v.strategy.strategyHash} (app ${v.strategy.app}, tx ${v.strategy.txHash}): ${v.reason} -- ${v.detail}`);
  }
  console.error("\nDock (revoke) the violating strategy/strategies, or choose a different Safe, before installing the Guard.");
  process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
