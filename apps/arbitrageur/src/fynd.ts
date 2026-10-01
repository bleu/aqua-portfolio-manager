import { encodingOptions, FyndError, type Address, type FyndClient, type Hex } from "@kayibal/fynd-client";

export { FyndClient, FyndError } from "@kayibal/fynd-client";

/// A route Fynd found to swap `amountIn` of one token into another, encoded as calldata this
/// server can hand straight to `Arbitrageur.executeFlashArbitrage` -- not something the caller
/// signs or submits itself (that's the client's own EOA-oriented `swapPayload`/`executeSwap`
/// flow, which this server deliberately doesn't use; see README's "Flash-loan execution"
/// section).
export interface FyndQuote {
  target: Address;
  spender: Address;
  calldata: Hex;
  expectedAmountOut: bigint;
}

export interface FyndQuoteParams {
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  sender: Address;
  slippageBps: bigint;
  minResponses?: number;
  timeoutMs?: number;
}

/// Uniswap V4's PoolManager allows only one active `unlock` session at a time. The executor's
/// own flash loan already holds that session for the full trade (see ADR-0014's Decision), so a
/// Fynd-routed Market Leg that itself opens a second one -- Fynd's Uniswap V4 execution path
/// does this per swap group -- would revert with `AlreadyUnlocked`. Excluded here, not worked
/// around, since the executor has no way to nest into an already-open session.
const EXCLUDED_PROTOCOLS = ["uniswap_v4"];

/// One quote call to a locally-running Fynd server, via `@kayibal/fynd-client`. `sender` must be
/// the `Arbitrageur` contract's own address, not the EOA running this server -- it's the
/// contract that ends up holding and spending the tokens mid-flash-loan. `encodingOptions`
/// defaults to `transferType: 'transfer_from'`, so the router pulls tokens via a plain
/// `approve()`, never Permit2 -- a contract holding funds mid-transaction has no EOA available
/// to produce a Permit2 signature with.
export async function getFyndSwapCalldata(client: FyndClient, params: FyndQuoteParams): Promise<FyndQuote> {
  const { tokenIn, tokenOut, amountIn, sender, slippageBps, minResponses, timeoutMs } = params;

  const [quote, info] = await Promise.all([
    client.quote({
      order: { tokenIn, tokenOut, amount: amountIn, side: "sell", sender },
      options: {
        encodingOptions: encodingOptions(Number(slippageBps) / 10_000),
        routeFilter: { excludeProtocols: EXCLUDED_PROTOCOLS },
        minResponses,
        timeoutMs,
      },
    }),
    client.info(),
  ]);

  if (!quote.transaction) {
    throw FyndError.config("Fynd quote missing `transaction` -- encodingOptions was not honored");
  }
  if (quote.transaction.value !== 0n) {
    throw FyndError.config(
      `Fynd route requires sending ${quote.transaction.value} native value; the flash-loan call forwards none`,
    );
  }
  if (!info.routerAddress) {
    throw FyndError.config("Fynd instance has no routerAddress -- quote-only chain?");
  }
  // Defense in depth: `routeFilter` is a request, not a guarantee the solver honors it. A route
  // that touches the excluded protocol anyway must never reach the executor, since it would
  // revert the whole flash-loan transaction rather than just this leg.
  const usedExcludedProtocol = quote.route?.swaps.some((swap) => EXCLUDED_PROTOCOLS.includes(swap.protocol));
  if (usedExcludedProtocol) {
    throw FyndError.config(
      `Fynd route used an excluded protocol despite routeFilter (route: ${JSON.stringify(quote.route?.swaps.map((s) => s.protocol))})`,
    );
  }

  return {
    target: quote.transaction.to,
    spender: info.routerAddress,
    calldata: quote.transaction.data,
    expectedAmountOut: quote.amountOut,
  };
}
