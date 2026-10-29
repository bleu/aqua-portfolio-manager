import { keccak256 } from "viem";
import { describe, expect, it } from "vitest";
import { buildOrder, buildProgram, encodeOrder } from "./portfolioManagerEncoding";
import { buildReshipSteps, buildShipSteps, computeStrategyHash, type StrategyGroup } from "./safeProposal";

const MAKER = "0x71a4d045e3Dd40321b5A35e03ed9fc5a8e9F2c3b" as const;
const GROUPS: StrategyGroup[] = [
  { name: "Stablecoins", targetPct: 60, tokenAddresses: ["0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"] },
  { name: "Majors", targetPct: 40, tokenAddresses: ["0x4200000000000000000000000000000000000006"] },
];
const FEE_BPS_PM = 10_000_000n;
const MAX_DEVIATION_BPS_PM = 50_000_000n;

describe("computeStrategyHash", () => {
  it("is deterministic for identical inputs -- the exact property Aqua.ship()'s immutability check relies on", () => {
    const first = computeStrategyHash(MAKER, GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const second = computeStrategyHash(MAKER, GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    expect(first).toBe(second);
  });

  it("changes if the fee changes -- confirms changing a parameter is a real way to get a new hash", () => {
    const original = computeStrategyHash(MAKER, GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const higherFee = computeStrategyHash(MAKER, GROUPS, FEE_BPS_PM + 1_000_000n, MAX_DEVIATION_BPS_PM);
    expect(higherFee).not.toBe(original);
  });

  it("changes for a different maker -- the maker is baked into the hash, not an external dimension", () => {
    const makerA = computeStrategyHash(MAKER, GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const makerB = computeStrategyHash(
      "0x1111111111111111111111111111111111111111",
      GROUPS,
      FEE_BPS_PM,
      MAX_DEVIATION_BPS_PM,
    );
    expect(makerB).not.toBe(makerA);
  });
});

describe("buildShipSteps", () => {
  it("omits the Guard deploy/install steps when no factory address is configured -- the local test env (and any deployment before the factory itself ships) has none set", async () => {
    const steps = await buildShipSteps({
      safeAddress: MAKER,
      groups: GROUPS,
      feeBpsPm: FEE_BPS_PM,
      maxDeviationBpsPm: MAX_DEVIATION_BPS_PM,
      balances: {},
      tokenSymbols: {},
    });
    expect(steps.map((s) => s.kind)).toEqual(["approve", "approve", "attest", "ship"]);
  });
});

describe("buildReshipSteps", () => {
  const groupA: import("./portfolioManagerEncoding").Group = {
    weightWad: 500_000_000_000_000_000n, // 0.5e18 each, two groups sum to WAD
    members: [{ tokenIndex: 5, feedIndex: 7 }],
  };
  const groupB: import("./portfolioManagerEncoding").Group = {
    weightWad: 500_000_000_000_000_000n,
    members: [{ tokenIndex: 9, feedIndex: 3 }],
  };
  const program = buildProgram([groupA, groupB], FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
  const originalOrder = buildOrder(MAKER, program);
  const encodedOrder = encodeOrder(originalOrder);
  const tokens = GROUPS.flatMap((g) => g.tokenAddresses);

  it("builds approve + attest + ship only -- no Guard steps when no factory address is configured, same as buildShipSteps", async () => {
    const steps = await buildReshipSteps({
      encodedOrder,
      tokens,
      groupNames: ["Stablecoins", "Majors"],
      balances: {},
      tokenSymbols: {},
    });
    expect(steps.map((s) => s.kind)).toEqual(["approve", "approve", "attest", "ship"]);
  });

  it("produces a strategyHash different from the original -- the whole point of the nonce", async () => {
    const originalHash = keccak256(encodedOrder);
    const steps = await buildReshipSteps({ encodedOrder, tokens, groupNames: null, balances: {}, tokenSymbols: {} });
    const attestStep = steps.find((s) => s.kind === "attest")!;
    expect(attestStep.kind).toBe("attest");
    if (attestStep.kind === "attest") {
      expect(attestStep.strategyHash).not.toBe(originalHash);
    }
  });

  it("ships the exact tokens list passed in, unchanged", async () => {
    const steps = await buildReshipSteps({ encodedOrder, tokens, groupNames: null, balances: {}, tokenSymbols: {} });
    const shipStep = steps.find((s) => s.kind === "ship")!;
    for (const token of tokens) {
      expect(shipStep.data.toLowerCase()).toContain(token.slice(2).toLowerCase());
    }
  });
});
