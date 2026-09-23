import { describe, expect, it, vi } from "vitest";
import type { FyndClient } from "@kayibal/fynd-client";
import { FyndError, getFyndSwapCalldata } from "../src/fynd.js";

const TOKEN_A = "0x1111111111111111111111111111111111111111";
const TOKEN_B = "0x2222222222222222222222222222222222222222";
const SENDER = "0x3333333333333333333333333333333333333333";
const ROUTER = "0x4444444444444444444444444444444444444444";

/// `FyndClient`'s constructor talks to the network, so tests fake just the two methods
/// `getFyndSwapCalldata` actually calls rather than constructing a real client.
function fakeClient(overrides: { quote?: unknown; info?: unknown }): FyndClient {
  return {
    quote: overrides.quote ?? vi.fn(),
    info: overrides.info ?? vi.fn(),
  } as unknown as FyndClient;
}

describe("getFyndSwapCalldata", () => {
  const baseParams = { tokenIn: TOKEN_A, tokenOut: TOKEN_B, amountIn: 1000n, sender: SENDER, slippageBps: 50n };

  it("builds a sell-order request and maps a well-formed quote + info to a FyndQuote", async () => {
    const quoteMock = vi.fn(async () => ({
      transaction: { to: ROUTER, value: 0n, data: "0xdead" },
      amountOut: 999n,
    }));
    const infoMock = vi.fn(async () => ({ routerAddress: ROUTER, permit2Address: "0x", chainId: 8453 }));
    const client = fakeClient({ quote: quoteMock, info: infoMock });

    const quote = await getFyndSwapCalldata(client, baseParams);

    expect(quote).toEqual({ target: ROUTER, spender: ROUTER, calldata: "0xdead", expectedAmountOut: 999n });

    expect(quoteMock).toHaveBeenCalledWith({
      order: { tokenIn: TOKEN_A, tokenOut: TOKEN_B, amount: 1000n, side: "sell", sender: SENDER },
      options: { encodingOptions: expect.objectContaining({ slippage: 0.005, transferType: "transfer_from" }) },
    });
  });

  it("throws FyndError when the quote has no transaction (encodingOptions not honored)", async () => {
    const client = fakeClient({
      quote: vi.fn(async () => ({ amountOut: 999n })),
      info: vi.fn(async () => ({ routerAddress: ROUTER })),
    });

    await expect(getFyndSwapCalldata(client, baseParams)).rejects.toThrow(FyndError);
  });

  it("throws FyndError when the route requires nonzero native value", async () => {
    const client = fakeClient({
      quote: vi.fn(async () => ({ transaction: { to: ROUTER, value: 1n, data: "0xdead" }, amountOut: 999n })),
      info: vi.fn(async () => ({ routerAddress: ROUTER })),
    });

    await expect(getFyndSwapCalldata(client, baseParams)).rejects.toThrow(FyndError);
  });

  it("throws FyndError when the Fynd instance has no routerAddress", async () => {
    const client = fakeClient({
      quote: vi.fn(async () => ({ transaction: { to: ROUTER, value: 0n, data: "0xdead" }, amountOut: 999n })),
      info: vi.fn(async () => ({ routerAddress: null })),
    });

    await expect(getFyndSwapCalldata(client, baseParams)).rejects.toThrow(FyndError);
  });
});
