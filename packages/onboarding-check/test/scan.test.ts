/**
 * Integration test: real Anvil chain, real deployed Aqua (compiled from lib/aqua, same
 * pinned commit the other PoCs use -- see src/fixtures/aqua-artifact.json), real ship()
 * transactions. Not mocked -- same "run it against the real thing" standard the rest of
 * this repo's PoCs and simulation suite hold to.
 */

import { spawn, type ChildProcess } from "node:child_process";
import {
  createPublicClient,
  createWalletClient,
  http,
  keccak256,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { foundry } from "viem/chains";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  AQUA_ABI,
  AQUA_BYTECODE,
  checkOnboarding,
  classifyStrategy,
  reconstructDeclaredTokens,
  fetchShippedStrategies,
} from "../src/scan.js";

const ANVIL_PORT = 8547; // distinct from the repo's default 8545, avoid colliding with a dev chain
const RPC_URL = `http://127.0.0.1:${ANVIL_PORT}`;

// Anvil's well-known default account #0 private key -- test-only, never a real key.
const DEPLOYER_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as Hex;

let anvil: ChildProcess;

beforeAll(async () => {
  anvil = spawn("anvil", ["--port", String(ANVIL_PORT), "--silent"]);
  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("anvil did not start in time")), 15_000);
    const client = createPublicClient({ transport: http(RPC_URL) });
    const poll = setInterval(async () => {
      try {
        await client.getBlockNumber();
        clearTimeout(timeout);
        clearInterval(poll);
        resolve();
      } catch {
        // not ready yet
      }
    }, 200);
  });
}, 20_000);

afterAll(() => {
  anvil.kill();
});

// Fixed test addresses -- arbitrary, non-zero. Aqua's ship() never calls
// safeTransferFrom (confirmed by reading Aqua.sol directly), so these don't need to be
// real deployed ERC20s.
const TOKEN_A = "0x000000000000000000000000000000000000000a" as Address;
const TOKEN_B = "0x000000000000000000000000000000000000000b" as Address;
const TOKEN_C = "0x000000000000000000000000000000000000000c" as Address;
const APP = "0x0000000000000000000000000000000000001234" as Address; // truthy stand-in

describe("onboarding pre-existing-strategy check", () => {
  it("finds a real, on-chain-only-derivable violation and clears a compliant strategy", async () => {
    const deployer = privateKeyToAccount(DEPLOYER_KEY);
    const publicClient = createPublicClient({ transport: http(RPC_URL) });
    const walletClient = createWalletClient({ account: deployer, chain: foundry, transport: http(RPC_URL) });

    // Deploy the real, compiled Aqua contract.
    const deployHash = await walletClient.deployContract({
      abi: AQUA_ABI,
      bytecode: AQUA_BYTECODE,
    });
    const deployReceipt = await publicClient.waitForTransactionReceipt({ hash: deployHash });
    const aquaAddress = deployReceipt.contractAddress!;
    expect(aquaAddress).toBeTruthy();

    const maker = deployer.address; // ship()'s msg.sender becomes the maker

    // Strategy 1: PM's own trusted strategy -- touches tokens across two "groups" but is
    // exempt, same as the on-chain Guard's own PM-strategy exemption.
    const pmStrategyBytes = "0xdeadbeef" as Hex;
    const pmShipHash = await walletClient.writeContract({
      address: aquaAddress,
      abi: AQUA_ABI,
      functionName: "ship",
      args: [APP, pmStrategyBytes, [TOKEN_A, TOKEN_B], [1000n, 2000n]],
    });
    await publicClient.waitForTransactionReceipt({ hash: pmShipHash });

    // Aqua computes strategyHash = keccak256(strategy) on-chain; recompute the same way
    // here so the test's trusted hash matches exactly.
    const pmStrategyHash = keccak256(pmStrategyBytes);

    // Strategy 2: some OTHER strategy, compliant -- stays inside a single declared group.
    const compliantStrategyBytes = "0xc0ffee01" as Hex;
    const compliantShipHash = await walletClient.writeContract({
      address: aquaAddress,
      abi: AQUA_ABI,
      functionName: "ship",
      args: [APP, compliantStrategyBytes, [TOKEN_A], [500n]],
    });
    await publicClient.waitForTransactionReceipt({ hash: compliantShipHash });

    // Strategy 3: some OTHER strategy, VIOLATING -- crosses two declared groups.
    const violatingStrategyBytes = "0xbad00003" as Hex;
    const violatingShipHash = await walletClient.writeContract({
      address: aquaAddress,
      abi: AQUA_ABI,
      functionName: "ship",
      args: [APP, violatingStrategyBytes, [TOKEN_A, TOKEN_C], [700n, 300n]],
    });
    await publicClient.waitForTransactionReceipt({ hash: violatingShipHash });

    // Strategy 4: some OTHER strategy, touching a token OUTSIDE the declared universe.
    const unknownTokenAddress = "0x0000000000000000000000000000000000000fff" as Address;
    const outsideStrategyBytes = "0xbad00004" as Hex;
    const outsideShipHash = await walletClient.writeContract({
      address: aquaAddress,
      abi: AQUA_ABI,
      functionName: "ship",
      args: [APP, outsideStrategyBytes, [unknownTokenAddress], [42n]],
    });
    await publicClient.waitForTransactionReceipt({ hash: outsideShipHash });

    const groupConfig = {
      [TOKEN_A.toLowerCase()]: "group-1",
      [TOKEN_B.toLowerCase()]: "group-2",
      [TOKEN_C.toLowerCase()]: "group-2",
    };

    // --- Unit-level checks on the building blocks, not just the end-to-end result ---

    const shipped = await fetchShippedStrategies(publicClient, aquaAddress, maker, 0n, await publicClient.getBlockNumber());
    expect(shipped).toHaveLength(4);

    const reconstructedCompliant = await reconstructDeclaredTokens(
      publicClient,
      aquaAddress,
      shipped.find((s) => s.strategyHash.toLowerCase() === keccak256(compliantStrategyBytes).toLowerCase())!,
    );
    expect(reconstructedCompliant.tokens.map((t) => t.toLowerCase())).toEqual([TOKEN_A.toLowerCase()]);
    expect(classifyStrategy(reconstructedCompliant, groupConfig, pmStrategyHash)).toBeNull();

    const reconstructedViolating = await reconstructDeclaredTokens(
      publicClient,
      aquaAddress,
      shipped.find((s) => s.strategyHash.toLowerCase() === keccak256(violatingStrategyBytes).toLowerCase())!,
    );
    expect(reconstructedViolating.tokens.map((t) => t.toLowerCase()).sort()).toEqual(
      [TOKEN_A.toLowerCase(), TOKEN_C.toLowerCase()].sort(),
    );
    const violation = classifyStrategy(reconstructedViolating, groupConfig, pmStrategyHash);
    expect(violation?.reason).toBe("cross-group");

    const reconstructedPm = await reconstructDeclaredTokens(
      publicClient,
      aquaAddress,
      shipped.find((s) => s.strategyHash.toLowerCase() === pmStrategyHash.toLowerCase())!,
    );
    // PM's own strategy really does span two groups (A and B) -- proves the exemption is
    // doing real work, not passing by accident because it happened to be compliant anyway.
    expect(new Set(reconstructedPm.tokens.map((t) => groupConfig[t.toLowerCase()])).size).toBe(2);
    expect(classifyStrategy(reconstructedPm, groupConfig, pmStrategyHash)).toBeNull();

    // --- End-to-end: the top-level check refuses onboarding for the right reasons ---

    const result = await checkOnboarding(
      publicClient,
      aquaAddress,
      maker,
      groupConfig,
      pmStrategyHash,
      0n,
      await publicClient.getBlockNumber(),
    );

    expect(result.strategiesFound).toBe(4);
    expect(result.compliant).toBe(false);
    expect(result.violations).toHaveLength(2);
    expect(result.violations.map((v) => v.reason).sort()).toEqual(["cross-group", "outside-universe"]);
  }, 30_000);

  it("returns compliant when every pre-existing strategy stays inside one group", async () => {
    const deployer = privateKeyToAccount(DEPLOYER_KEY);
    const publicClient = createPublicClient({ transport: http(RPC_URL) });
    const walletClient = createWalletClient({ account: deployer, chain: foundry, transport: http(RPC_URL) });

    const deployHash = await walletClient.deployContract({
      abi: AQUA_ABI,
      bytecode: AQUA_BYTECODE,
    });
    const deployReceipt = await publicClient.waitForTransactionReceipt({ hash: deployHash });
    const aquaAddress = deployReceipt.contractAddress!;

    const strategyBytes = "0x1111" as Hex;
    const shipHash = await walletClient.writeContract({
      address: aquaAddress,
      abi: AQUA_ABI,
      functionName: "ship",
      args: [APP, strategyBytes, [TOKEN_A], [1n]],
    });
    await publicClient.waitForTransactionReceipt({ hash: shipHash });

    const someOtherTrustedHash = keccak256("0x9999" as Hex); // not this maker's strategy at all

    const result = await checkOnboarding(
      publicClient,
      aquaAddress,
      deployer.address,
      { [TOKEN_A.toLowerCase()]: "group-1" },
      someOtherTrustedHash,
      0n,
      await publicClient.getBlockNumber(),
    );

    expect(result.strategiesFound).toBe(1);
    expect(result.compliant).toBe(true);
    expect(result.violations).toHaveLength(0);
  }, 30_000);
});
