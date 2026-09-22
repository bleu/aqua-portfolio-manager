import { afterEach, describe, expect, it, vi } from "vitest";
import { FyndQuoteError, getFyndSwapCalldata, parseFyndQuoteResponse } from "../src/fynd.js";

const TOKEN_A = "0x1111111111111111111111111111111111111111";
const TOKEN_B = "0x2222222222222222222222222222222222222222";
const SENDER = "0x3333333333333333333333333333333333333333";
const ROUTER = "0x4444444444444444444444444444444444444444";

describe("parseFyndQuoteResponse", () => {
  it("extracts target/spender/calldata/expectedAmountOut from a well-formed response", () => {
    const quote = parseFyndQuoteResponse({
      transaction: { to: ROUTER, data: "0xabcdef" },
      spender: ROUTER,
      amountOut: "12345",
    });

    expect(quote).toEqual({
      target: ROUTER,
      spender: ROUTER,
      calldata: "0xabcdef",
      expectedAmountOut: 12345n,
    });
  });

  it("falls back to the transaction target when spender is omitted", () => {
    const quote = parseFyndQuoteResponse({ transaction: { to: ROUTER, data: "0x00" }, amountOut: 0 });
    expect(quote.spender).toBe(ROUTER);
  });

  it("throws FyndQuoteError when transaction.to/data is missing", () => {
    expect(() => parseFyndQuoteResponse({ amountOut: "1" })).toThrow(FyndQuoteError);
    expect(() => parseFyndQuoteResponse({ transaction: { to: ROUTER }, amountOut: "1" })).toThrow(FyndQuoteError);
  });

  it("throws FyndQuoteError when amountOut is missing", () => {
    expect(() => parseFyndQuoteResponse({ transaction: { to: ROUTER, data: "0x00" } })).toThrow(FyndQuoteError);
  });
});

describe("getFyndSwapCalldata", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("posts a sell-order quote request and parses the response", async () => {
    const fetchMock = vi.fn(async () =>
      new Response(
        JSON.stringify({ transaction: { to: ROUTER, data: "0xdead" }, spender: ROUTER, amountOut: "999" }),
        { status: 200 },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    const quote = await getFyndSwapCalldata({
      fyndUrl: "http://127.0.0.1:4000/",
      chain: "base",
      tokenIn: TOKEN_A,
      tokenOut: TOKEN_B,
      amountIn: 1000n,
      sender: SENDER,
      slippageBps: 50n,
    });

    expect(quote).toEqual({ target: ROUTER, spender: ROUTER, calldata: "0xdead", expectedAmountOut: 999n });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0]!;
    expect(url).toBe("http://127.0.0.1:4000/v1/base/quote");
    expect(init?.method).toBe("POST");
    const body = JSON.parse(init?.body as string);
    expect(body).toEqual({
      order: { tokenIn: TOKEN_A, tokenOut: TOKEN_B, amount: "1000", side: "sell", sender: SENDER },
      options: { slippage: 0.005 },
    });
  });

  it("throws FyndQuoteError on a non-ok HTTP response", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("server error", { status: 500 })),
    );

    await expect(
      getFyndSwapCalldata({
        fyndUrl: "http://127.0.0.1:4000",
        chain: "base",
        tokenIn: TOKEN_A,
        tokenOut: TOKEN_B,
        amountIn: 1000n,
        sender: SENDER,
        slippageBps: 50n,
      }),
    ).rejects.toThrow(FyndQuoteError);
  });
});
