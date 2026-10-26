import { decodeFunctionData, type Address, type Hex } from "viem";
import { describe, expect, it } from "vitest";
import { buildBatchedTransaction } from "./safeProposal";

const MULTISEND_ABI = [
  { type: "function", name: "multiSend", stateMutability: "payable", inputs: [{ name: "transactions", type: "bytes" }], outputs: [] },
] as const;

/** Mirrors MultiSendCallOnly.sol's own assembly unpacking loop exactly (1 byte operation + 20
 *  bytes to + 32 bytes value + 32 bytes dataLength + data, repeated) -- the only way to verify
 *  buildBatchedTransaction's packing is actually correct is to unpack it the same way the real
 *  contract would and check what comes back out, not just eyeball the packed bytes. */
function decodeMultiSend(packed: Hex): { operation: number; to: Address; value: bigint; data: Hex }[] {
  const bytes = packed.slice(2);
  const calls: { operation: number; to: Address; value: bigint; data: Hex }[] = [];
  let i = 0;
  while (i < bytes.length) {
    const operation = parseInt(bytes.slice(i, i + 2), 16);
    const to = `0x${bytes.slice(i + 2, i + 42)}` as Address;
    const value = BigInt(`0x${bytes.slice(i + 42, i + 106)}`);
    const dataLength = parseInt(bytes.slice(i + 106, i + 170), 16);
    const data = `0x${bytes.slice(i + 170, i + 170 + dataLength * 2)}` as Hex;
    calls.push({ operation, to, value, data });
    i += 170 + dataLength * 2;
  }
  return calls;
}

describe("buildBatchedTransaction", () => {
  it("returns the single call directly, unwrapped, when there's only one", () => {
    const call = { to: "0x1111111111111111111111111111111111111111" as Address, data: "0xdeadbeef" as Hex };
    expect(buildBatchedTransaction([call])).toEqual(call);
  });

  it("round-trips multiple calls through MultiSendCallOnly's own packed encoding", () => {
    const calls = [
      { to: "0x1111111111111111111111111111111111111111" as Address, data: "0xaabbccdd" as Hex },
      { to: "0x2222222222222222222222222222222222222222" as Address, data: "0x095ea7b3" as Hex },
      { to: "0x3333333333333333333333333333333333333333" as Address, data: "0x1234" as Hex },
    ];

    const { to, data } = buildBatchedTransaction(calls);
    const { args } = decodeFunctionData({ abi: MULTISEND_ABI, data });
    const decoded = decodeMultiSend(args[0]);

    expect(decoded).toHaveLength(3);
    decoded.forEach((call, i) => {
      expect(call.operation).toBe(0); // Call, never DelegateCall -- MultiSendCallOnly reverts on 1
      expect(call.value).toBe(0n);
      expect(call.to.toLowerCase()).toBe(calls[i]!.to.toLowerCase());
      expect(call.data).toBe(calls[i]!.data);
    });
    expect(to).not.toBe(calls[0]!.to); // routed through MultiSendCallOnly, not the first call's own target
  });

  it("round-trips a call with odd-length (non-selector-only) data correctly", () => {
    const longData = `0x${"ab".repeat(100)}` as Hex;
    const calls = [{ to: "0x4444444444444444444444444444444444444444" as Address, data: longData }];
    // Force the multi-call path even for one real call, by padding with a second no-op-shaped one.
    const padded = [...calls, { to: "0x5555555555555555555555555555555555555555" as Address, data: "0x" as Hex }];

    const { data } = buildBatchedTransaction(padded);
    const { args } = decodeFunctionData({ abi: MULTISEND_ABI, data });
    const decoded = decodeMultiSend(args[0]);

    expect(decoded[0]!.data).toBe(longData);
    expect(decoded[1]!.data).toBe("0x");
  });
});
