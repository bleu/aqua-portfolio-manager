import { describe, expect, it } from "vitest";
import { computeStrategyHash, type StrategyGroup } from "./safeProposal";

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
