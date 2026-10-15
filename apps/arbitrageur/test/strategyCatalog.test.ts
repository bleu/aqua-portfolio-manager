import { describe, expect, it } from "vitest";
import { evaluateEligibility } from "../src/domains/strategyCatalog.js";

const USDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
const WETH = "0x4200000000000000000000000000000000000006";
const UNKNOWN = "0x9999999999999999999999999999999999999999";
const USDC_FEED = "0x7e860098f58bbfc8648a4311b374b1d669a2bc6b";
const WETH_FEED = "0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70";
const UNKNOWN_FEED = "0x8888888888888888888888888888888888888888";
const ALLOWED_TOKENS = new Set([USDC, WETH]) as ReadonlySet<`0x${string}`>;
const ALLOWED_FEEDS = new Set([USDC_FEED, WETH_FEED]) as ReadonlySet<`0x${string}`>;

function decodedWithMembers(members: { token: string; feed: string }[]) {
  return { groups: [{ members: members.map((m) => ({ token: m.token as `0x${string}`, feed: m.feed as `0x${string}` })) }] };
}

function decodedWithTokens(tokens: string[]) {
  return decodedWithMembers(tokens.map((token) => ({ token, feed: USDC_FEED })));
}

describe("evaluateEligibility", () => {
  it("is eligible when every declared token and feed is on its allow list", () => {
    const decoded = decodedWithMembers([
      { token: USDC, feed: USDC_FEED },
      { token: WETH, feed: WETH_FEED },
    ]);
    expect(evaluateEligibility(decoded, ALLOWED_TOKENS, ALLOWED_FEEDS)).toEqual({
      eligible: true,
      reason: undefined,
    });
  });

  it("is ineligible with a reason naming the unsupported token", () => {
    const result = evaluateEligibility(decodedWithTokens([USDC, UNKNOWN]), ALLOWED_TOKENS, ALLOWED_FEEDS);
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe(`unsupported-token:${UNKNOWN}`);
  });

  it("lists each unsupported token once, even if it appears in multiple groups", () => {
    const decoded = {
      groups: [
        { members: [{ token: UNKNOWN as `0x${string}`, feed: USDC_FEED as `0x${string}` }] },
        { members: [{ token: UNKNOWN as `0x${string}`, feed: USDC_FEED as `0x${string}` }] },
      ],
    };
    expect(evaluateEligibility(decoded, ALLOWED_TOKENS, ALLOWED_FEEDS).reason).toBe(`unsupported-token:${UNKNOWN}`);
  });

  it("compares tokens case-insensitively", () => {
    const upper = USDC.toUpperCase().replace("0X", "0x") as `0x${string}`;
    expect(evaluateEligibility(decodedWithTokens([upper]), ALLOWED_TOKENS, ALLOWED_FEEDS).eligible).toBe(true);
  });

  it("is ineligible with a reason naming an allowed token paired with an unsupported feed", () => {
    const decoded = decodedWithMembers([{ token: USDC, feed: UNKNOWN_FEED }]);
    const result = evaluateEligibility(decoded, ALLOWED_TOKENS, ALLOWED_FEEDS);
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe(`unsupported-feed:${UNKNOWN_FEED}`);
  });

  it("compares feeds case-insensitively", () => {
    const upperFeed = USDC_FEED.toUpperCase().replace("0X", "0x") as `0x${string}`;
    const decoded = decodedWithMembers([{ token: USDC, feed: upperFeed }]);
    expect(evaluateEligibility(decoded, ALLOWED_TOKENS, ALLOWED_FEEDS).eligible).toBe(true);
  });

  it("checks tokens before feeds -- an unsupported token is reported even if its feed is also bad", () => {
    const decoded = decodedWithMembers([{ token: UNKNOWN, feed: UNKNOWN_FEED }]);
    const result = evaluateEligibility(decoded, ALLOWED_TOKENS, ALLOWED_FEEDS);
    expect(result.reason).toBe(`unsupported-token:${UNKNOWN}`);
  });
});
