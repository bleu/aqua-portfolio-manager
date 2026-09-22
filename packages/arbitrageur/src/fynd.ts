import { isAddress, type Address, type Hex } from "viem";

/// A route Fynd found to swap `amountIn` of one token into another, encoded as calldata this
/// server can hand straight to `Arbitrageur.executeFlashArbitrage` -- not something the caller
/// signs or submits itself (that's Fynd's *other*, EOA-oriented client flow, which this server
/// deliberately doesn't use; see README's "Fynd integration" section).
export interface FyndQuote {
  target: Address;
  spender: Address;
  calldata: Hex;
  expectedAmountOut: bigint;
}

export interface FyndQuoteParams {
  fyndUrl: string;
  chain: string;
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  sender: Address;
  slippageBps: bigint;
  timeoutMs: number;
}

export class FyndQuoteError extends Error {}

/// One POST to a locally-running Fynd server's raw HTTP API (`fynd serve --chain <chain>`, see
/// README). `sender` must be the `Arbitrageur` contract's own address, not the EOA running this
/// server -- it's the contract that ends up holding and spending the tokens mid-flash-loan.
/// Bounded by `timeoutMs`: this runs inside an unattended polling loop, and `fetch` has no
/// default timeout -- a hung Fynd server would otherwise stall every future tick, not just fail
/// this one.
export async function getFyndSwapCalldata(params: FyndQuoteParams): Promise<FyndQuote> {
  const { fyndUrl, chain, tokenIn, tokenOut, amountIn, sender, slippageBps, timeoutMs } = params;

  const url = `${fyndUrl.replace(/\/$/, "")}/v1/${chain}/quote`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      order: { tokenIn, tokenOut, amount: amountIn.toString(), side: "sell", sender },
      options: { slippage: Number(slippageBps) / 10_000 },
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!response.ok) {
    throw new FyndQuoteError(`Fynd quote request failed: ${response.status} ${await response.text()}`);
  }

  return parseFyndQuoteResponse(await response.json());
}

/// Field-name mapping kept in its own function, separate from the fetch above, so it's a
/// one-function fix if these don't match Fynd's real response shape -- unverified against a live
/// server; see README's "Fynd integration" section.
export function parseFyndQuoteResponse(json: unknown): FyndQuote {
  const body = json as Record<string, unknown>;
  const tx = body.transaction as Record<string, unknown> | undefined;

  if (!tx || typeof tx.to !== "string" || typeof tx.data !== "string" || !isAddress(tx.to)) {
    throw new FyndQuoteError(`Unexpected Fynd quote response shape: ${JSON.stringify(json)}`);
  }
  const spender = typeof body.spender === "string" ? body.spender : tx.to;
  if (!isAddress(spender)) {
    throw new FyndQuoteError(`Fynd quote response has an invalid spender address: ${JSON.stringify(json)}`);
  }
  if (typeof body.amountOut !== "string" && typeof body.amountOut !== "number") {
    throw new FyndQuoteError(`Fynd quote response missing amountOut: ${JSON.stringify(json)}`);
  }

  return {
    target: tx.to,
    spender,
    calldata: tx.data as Hex,
    expectedAmountOut: BigInt(body.amountOut as string | number),
  };
}
