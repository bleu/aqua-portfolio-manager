import { encodeFunctionData, erc20Abi, maxUint256, type Address, type Hex } from "viem";
import { AQUA_ADDRESS, PM_ROUTER_ADDRESS, PM_STRATEGY_VALIDATOR_ADDRESS } from "./contracts";
import { buildOrder, buildProgram, encodeOrder, type Group } from "./portfolioManagerEncoding";
import { getRegistryIndex } from "./tokenFeeds";

/** A single step's own round trip through the wallet (mobile push notification, user action,
 *  response) can take a while -- generous, but still bounded per step, so a stalled step can't
 *  freeze the whole multi-step flow forever. Applied per eth_sendTransaction call, not once for
 *  the whole sequence, since that sequence can now be several steps long. */
const STEP_TIMEOUT_MS = 90_000;
export const STEP_TIMEOUT_MESSAGE = "__aqua_pm_create_transaction_step_timeout__";

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, timeoutMessage: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(timeoutMessage)), timeoutMs);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

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
   *  strategy must sum to (approximately) 100 -- see toEncodingGroups' own rounding note. */
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
   *  routes every signing request through the wallet's own UI, never a private key this app
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
  /** Fires after each step's eth_sendTransaction call resolves, for progress UI. */
  onStepComplete?: (step: { index: number; total: number; label: string; txHash: Hex }) => void;
};

export type ProposeShipStrategyResult = {
  /** The final step's transaction hash -- Aqua.ship(), the call that actually activates the
   *  strategy. */
  txHash: Hex;
};

/** Ships a strategy (per-token approve + attestBuildParameters + ship, matching
 *  packages/contracts/script/ShipTestStrategy.s.sol's own sequence) as a series of ordinary
 *  eth_sendTransaction calls through the connected wallet -- the same request shape any dApp
 *  sends to any wallet. A connected Safe{Wallet} session turns each one into a normal multisig
 *  approval on its own, the same way it would for any other dApp's transaction request.
 *
 *  This app previously tried building a single batched transaction and submitting a hand-crafted
 *  Safe signature directly to Safe's own backend (via @safe-global/protocol-kit + api-kit). That
 *  approach failed repeatedly and unpredictably over a WalletConnect-connected session -- the
 *  signature Safe{Wallet} returned was never valid by Safe's own server-side check, regardless of
 *  which address or EIP-712 signing method was used to request it. Plain eth_sendTransaction
 *  avoids all of that: it's the standard, universally-supported request shape, and Safe{Wallet}
 *  (not this app) owns every Safe-specific detail of turning it into a real multisig transaction.
 *  The cost: each step is now its own separate transaction instead of one atomic batch, so a
 *  single-owner Safe sees 2-4 sequential approval prompts instead of one. */
export async function proposeShipStrategyTransaction({
  safeAddress,
  provider,
  groups,
  feeBpsPm,
  maxDeviationBpsPm,
  balances,
  onStepComplete,
}: ProposeShipStrategyParams): Promise<ProposeShipStrategyResult> {
  const encodingGroups = toEncodingGroups(groups);
  const program = buildProgram(encodingGroups, feeBpsPm, maxDeviationBpsPm);
  const order = buildOrder(safeAddress, program);
  const encodedOrder = encodeOrder(order);

  const tokens = groups.flatMap((g) => g.tokenAddresses);
  const uniqueTokens = [...new Set(tokens)];
  const amounts = tokens.map((t) => balances[t] ?? 0n);
  const groupNames = groups.map((g) => g.name);

  const steps: { label: string; to: Address; data: Hex }[] = [
    ...uniqueTokens.map(
      (token): { label: string; to: Address; data: Hex } => ({
        label: `Approve ${token}`,
        to: token,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [AQUA_ADDRESS, maxUint256] }),
      }),
    ),
    {
      label: "Attest strategy parameters",
      to: PM_STRATEGY_VALIDATOR_ADDRESS,
      data: encodeFunctionData({
        abi: VALIDATOR_ABI,
        functionName: "attestBuildParameters",
        args: [order, tokens, groupNames],
      }),
    },
    {
      label: "Ship strategy",
      to: AQUA_ADDRESS,
      data: encodeFunctionData({
        abi: AQUA_ABI,
        functionName: "ship",
        args: [PM_ROUTER_ADDRESS, encodedOrder, tokens, amounts],
      }),
    },
  ];

  let txHash: Hex | undefined;
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]!;
    txHash = (await withTimeout(
      provider.request({
        method: "eth_sendTransaction",
        params: [{ from: safeAddress, to: step.to, data: step.data, value: "0x0" }],
      }),
      STEP_TIMEOUT_MS,
      STEP_TIMEOUT_MESSAGE,
    )) as Hex;
    onStepComplete?.({ index: i, total: steps.length, label: step.label, txHash });
  }

  if (!txHash) {
    throw new Error("No transactions were sent.");
  }
  return { txHash };
}
