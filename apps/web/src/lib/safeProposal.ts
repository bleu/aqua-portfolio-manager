import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import type { MetaTransactionData } from "@safe-global/types-kit";
import { encodeFunctionData, erc20Abi, maxUint256, recoverAddress, type Address, type Hex } from "viem";
import { base } from "wagmi/chains";
import { AQUA_ADDRESS, PM_ROUTER_ADDRESS, PM_STRATEGY_VALIDATOR_ADDRESS } from "./contracts";
import { buildOrder, buildProgram, encodeOrder, type Group } from "./portfolioManagerEncoding";
import { getRegistryIndex } from "./tokenFeeds";

const VALIDATOR_ABI = [
  {
    type: "function",
    name: "attestBuildParameters",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "order",
        type: "tuple",
        components: [
          { name: "maker", type: "address" },
          { name: "traits", type: "uint256" },
          { name: "data", type: "bytes" },
        ],
      },
      { name: "tokens", type: "address[]" },
      { name: "groupNames", type: "string[]" },
    ],
    outputs: [],
  },
] as const;

const AQUA_ABI = [
  {
    type: "function",
    name: "ship",
    stateMutability: "nonpayable",
    inputs: [
      { name: "app", type: "address" },
      { name: "strategy", type: "bytes" },
      { name: "tokens", type: "address[]" },
      { name: "amounts", type: "uint256[]" },
    ],
    outputs: [{ name: "strategyHash", type: "bytes32" }],
  },
] as const;

export type StrategyGroup = {
  name: string;
  /** Target weight as a percentage, e.g. 60 for 60%. Every group's targetPct across the whole
   *  strategy must sum to (approximately) 100 -- see buildShipTransactions' own rounding note. */
  targetPct: number;
  tokenAddresses: Address[];
};

/** Every member gets its own feed -- the wizard has no UI yet for designating a group's numeraire
 *  (PortfolioManagerArgsCodec.Member.feedIndex = 0), so this never sets one. */
function toEncodingGroups(groups: StrategyGroup[]): Group[] {
  const totalTargetPct = groups.reduce((sum, g) => sum + g.targetPct, 0);
  if (totalTargetPct <= 0) {
    throw new Error("Target allocations must sum to a positive percentage.");
  }

  const WAD = 1_000_000_000_000_000_000n;
  let compactSum = 0n;
  return groups.map((g, i) => {
    // Last group absorbs whatever rounding lost on the earlier ones, the same technique
    // PortfolioManagerArgsCodec.build itself uses for its own compact weights -- guarantees the
    // WAD weights this function hands to buildArgs sum to exactly WAD, which build() requires.
    const weightWad =
      i === groups.length - 1
        ? WAD - compactSum
        : (BigInt(Math.round(g.targetPct * 1_000_000)) * WAD) / BigInt(Math.round(totalTargetPct * 1_000_000));
    compactSum += weightWad;

    return {
      weightWad,
      members: g.tokenAddresses.map((tokenAddress) => {
        const index = getRegistryIndex(tokenAddress);
        return { tokenIndex: index, feedIndex: index };
      }),
    };
  });
}

export type ProposeShipStrategyParams = {
  safeAddress: Address;
  /** The connected wallet's own EIP-1193 provider (e.g. from wagmi's `connector.getProvider()`) --
   *  routes every signing request through Safe{Wallet}'s own UI, never a private key this app
   *  handles directly. */
  provider: { request: (args: { method: string; params?: unknown[] | object }) => Promise<unknown> };
  groups: StrategyGroup[];
  /** PM_BPS-scaled (1e9 = 100%): e.g. 5_000_000n for the 0.5% floor. */
  feeBpsPm: bigint;
  /** PM_BPS-scaled price-deviation circuit breaker; 0n disables it. */
  maxDeviationBpsPm: bigint;
  /** Real on-chain balances (raw integer units) for every token across every group, keyed by
   *  checksummed address -- read fresh at propose-time, not reused from a UI display value, so
   *  this never round-trips through a float. */
  balances: Record<Address, bigint>;
};

export type ProposeShipStrategyResult = {
  safeTxHash: Hex;
};

/** Builds the real "ship a strategy" batch (per-token approve + attestBuildParameters + ship,
 *  matching packages/contracts/script/ShipTestStrategy.s.sol's own sequence) and proposes it
 *  through Safe's Transaction Service -- signed by the connected wallet via the Safe App bridge,
 *  never by a private key this code holds. The Safe's other owners then see it as a pending
 *  signature in Safe{Wallet}, same as any other proposed transaction. */
export async function proposeShipStrategyTransaction({
  safeAddress,
  provider,
  groups,
  feeBpsPm,
  maxDeviationBpsPm,
  balances,
}: ProposeShipStrategyParams): Promise<ProposeShipStrategyResult> {
  const apiKey = process.env.NEXT_PUBLIC_SAFE_API_KEY;
  if (!apiKey) {
    throw new Error(
      "Missing NEXT_PUBLIC_SAFE_API_KEY -- get a free key at https://developer.safe.global and set it in " +
        "apps/web/.env.local (and in Vercel's project settings for production).",
    );
  }

  const encodingGroups = toEncodingGroups(groups);
  const program = buildProgram(encodingGroups, feeBpsPm, maxDeviationBpsPm);
  const order = buildOrder(safeAddress, program);
  const encodedOrder = encodeOrder(order);

  const tokens = groups.flatMap((g) => g.tokenAddresses);
  const uniqueTokens = [...new Set(tokens)];
  const amounts = tokens.map((t) => balances[t] ?? 0n);
  const groupNames = groups.map((g) => g.name);

  const transactions: MetaTransactionData[] = [
    ...uniqueTokens.map(
      (token): MetaTransactionData => ({
        to: token,
        value: "0",
        data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [AQUA_ADDRESS, maxUint256] }),
      }),
    ),
    {
      to: PM_STRATEGY_VALIDATOR_ADDRESS,
      value: "0",
      data: encodeFunctionData({
        abi: VALIDATOR_ABI,
        functionName: "attestBuildParameters",
        args: [order, tokens, groupNames],
      }),
    },
    {
      to: AQUA_ADDRESS,
      value: "0",
      data: encodeFunctionData({
        abi: AQUA_ABI,
        functionName: "ship",
        args: [PM_ROUTER_ADDRESS, encodedOrder, tokens, amounts],
      }),
    },
  ];

  const protocolKit = await Safe.init({ provider, signer: safeAddress, safeAddress });
  const apiKit = new SafeApiKit({ chainId: BigInt(base.id), apiKey });
  const safeTransaction = await protocolKit.createTransaction({ transactions, onlyCalls: true });
  const safeTxHash = (await protocolKit.getTransactionHash(safeTransaction)) as Hex;

  // The same baskets/targets/parameters always hash to the same safeTxHash -- so retrying after an
  // earlier attempt that appeared to fail client-side (e.g. the network call actually succeeded
  // server-side after this app had already given up and shown a timeout) asks the wallet to sign a
  // hash it's already signed, which it refuses ("message already signed") instead of just
  // re-returning the old signature. Checking first means a retry recovers straight into the
  // existing pending transaction instead of dead-ending on that wallet-side refusal.
  try {
    await apiKit.getTransaction(safeTxHash);
    console.log("[safeProposal] this exact transaction was already proposed earlier -- reusing it:", safeTxHash);
    return { safeTxHash };
  } catch {
    // Not found (or some other lookup failure) -- fall through and propose it fresh, as normal.
  }

  // signHash() signs the bare hash bytes (eth_sign-style) -- Safe{Wallet} can't tell that's meant
  // to confirm a specific pending transaction, and instead records it as a standalone "SafeMessage"
  // signature, which the Transaction Service then rejects as not matching this safeTxHash.
  //
  // signTransaction() looked like the right replacement, but it hard-validates that `signer` is
  // one of the Safe's own owners ("Transactions can only be signed by Safe owners") -- a check
  // meant for "I configured this SDK with a specific owner's key directly." It doesn't fit here:
  // `signer` above is the connected Safe's own address, not an owner, because this app is always
  // connected AS the Safe itself (via the Safe App bridge or WalletConnect-to-Safe{Wallet}), which
  // transparently substitutes the real owner's signature on the other end. signTypedData() is the
  // lower-level primitive that does the same EIP-712 signing without that extra membership check.
  const signature = await protocolKit.signTypedData(safeTransaction, "v4");

  // The Transaction Service's `senderAddress` must be the real owner who produced the signature,
  // not the Safe's own address -- same class of mix-up as signTransaction()'s owner check above,
  // now enforced server-side instead. The EIP-1193 provider never tells this app which owner
  // Safe{Wallet} actually signed with (it only returns raw signature bytes).
  //
  // First attempt here independently rebuilt the EIP-712 typed data and recovered against that --
  // it recovered a *third*, unrelated address, meaning that reconstruction didn't exactly match
  // what signTypedData() actually had the wallet sign (a version-string or field mismatch
  // somewhere). safeTxHash (above) is already the exact EIP-712 digest protocol-kit itself used to
  // request the signature, so recovering directly against that hash -- no independent
  // reconstruction -- can't drift out of sync with it.
  const senderAddress = await recoverAddress({ hash: safeTxHash, signature: signature.data as Hex });

  console.log("[safeProposal] signed, recovered sender:", senderAddress, "-- posting to Safe's Transaction Service now");
  await apiKit.proposeTransaction({
    safeAddress,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress,
    senderSignature: signature.data,
  });
  console.log("[safeProposal] proposeTransaction succeeded:", safeTxHash);

  return { safeTxHash };
}
