import { describe, expect, it } from "vitest";
import { buildDockTransaction, buildRemoveGuardTransaction } from "./dockProposal";

const STRATEGY_HASH = "0x1111111111111111111111111111111111111111111111111111111111111111" as const;
const TOKENS = ["0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", "0x4200000000000000000000000000000000000006"] as const;

describe("buildDockTransaction", () => {
  it("targets Aqua and uses dock(address,bytes32,address[])'s real selector", () => {
    const { to, data } = buildDockTransaction(STRATEGY_HASH, [...TOKENS]);

    expect(to).toBe(process.env.NEXT_PUBLIC_AQUA_ADDRESS);
    // toFunctionSelector("dock(address,bytes32,address[])"), matching IAqua.sol's dock().
    expect(data.slice(0, 10)).toBe("0x28defc17");
  });

  it("encodes the PM router as the app, and the exact strategyHash and tokens passed in", () => {
    const { data } = buildDockTransaction(STRATEGY_HASH, [...TOKENS]);

    const pmRouter = process.env.NEXT_PUBLIC_PM_ROUTER_ADDRESS!.slice(2).toLowerCase();
    expect(data.toLowerCase()).toContain(pmRouter);
    expect(data.toLowerCase()).toContain(STRATEGY_HASH.slice(2));
    for (const token of TOKENS) {
      expect(data.toLowerCase()).toContain(token.slice(2).toLowerCase());
    }
  });
});

describe("buildRemoveGuardTransaction", () => {
  it("targets the Safe itself and calls setGuard(address(0))", () => {
    const safeAddress = "0x71a4d045e3Dd40321b5A35e03ed9fc5a8e9F2c3b" as const;
    const { to, data } = buildRemoveGuardTransaction(safeAddress);

    expect(to).toBe(safeAddress);
    // toFunctionSelector("setGuard(address)"), matching GuardManager.sol's own setGuard().
    expect(data.slice(0, 10)).toBe("0xe19a9dd9");
    expect(data.slice(10)).toBe("0".repeat(64));
  });
});
