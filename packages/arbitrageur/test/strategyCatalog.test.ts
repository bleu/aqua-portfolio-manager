import { describe, expect, it } from "vitest";
import { evaluateEligibility } from "../src/domains/strategyCatalog.js";

const USDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
const WETH = "0x4200000000000000000000000000000000000006";
const UNKNOWN = "0x9999999999999999999999999999999999999999";
const ALLOWED = new Set([USDC, WETH]) as ReadonlySet<`0x${string}`>;

function decodedWithTokens(tokens: string[]) {
  return { groups: [{ members: tokens.map((token) => ({ token: token as `0x${string}` })) }] };
}

describe("evaluateEligibility", () => {
  it("is eligible when every declared token is on the allow list", () => {
    expect(evaluateEligibility(decodedWithTokens([USDC, WETH]), ALLOWED)).toEqual({
      eligible: true,
      reason: undefined,
    });
  });

  it("is ineligible with a reason naming the unsupported token", () => {
    const result = evaluateEligibility(decodedWithTokens([USDC, UNKNOWN]), ALLOWED);
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe(`unsupported-token:${UNKNOWN}`);
  });

  it("lists each unsupported token once, even if it appears in multiple groups", () => {
    const decoded = {
      groups: [{ members: [{ token: UNKNOWN as `0x${string}` }] }, { members: [{ token: UNKNOWN as `0x${string}` }] }],
    };
    expect(evaluateEligibility(decoded, ALLOWED).reason).toBe(`unsupported-token:${UNKNOWN}`);
  });

  it("compares case-insensitively", () => {
    const upper = USDC.toUpperCase().replace("0X", "0x") as `0x${string}`;
    expect(evaluateEligibility(decodedWithTokens([upper]), ALLOWED).eligible).toBe(true);
  });
});
