import {
  concatHex,
  createPublicClient,
  encodeFunctionData,
  encodePacked,
  erc20Abi,
  http,
  keccak256,
  maxUint256,
  type Address,
  type Hex,
} from "viem";
import { base } from "wagmi/chains";
import { AQUA_ADDRESS, PM_ROUTER_ADDRESS, PM_STRATEGY_VALIDATOR_ADDRESS } from "./contracts";
import { buildOrder, buildProgram, encodeOrder, type Group } from "./portfolioManagerEncoding";
import { getRegistryIndex } from "./tokenFeeds";

/** Safe's own canonical MultiSendCallOnly deployment (v1.3.0, same address on every chain Safe
 *  deploys to) -- verified directly against Base mainnet, not assumed: real bytecode present,
 *  exposes exactly multiSend(bytes)'s selector (0x8d80ff0a), and its runtime bytecode's call loop
 *  has no reachable delegatecall path, matching
 *  packages/contracts/lib/safe-smart-account/contracts/libraries/MultiSendCallOnly.sol exactly.
 *  Deliberately CallOnly, not the plain MultiSend contract -- this app never needs delegatecall,
 *  and CallOnly's narrower guarantee is one less thing to get wrong signing a batch blind. */
const MULTISEND_CALL_ONLY_ADDRESS: Address = "0x40A2aCCbd92BCA938b02010E17A5b8929b49130D";

const MULTISEND_ABI = [
  { type: "function", name: "multiSend", stateMutability: "payable", inputs: [{ name: "transactions", type: "bytes" }], outputs: [] },
] as const;

/** Packs one call the exact way MultiSendCallOnly's own assembly loop unpacks it: 1 byte
 *  operation (always 0, Call -- this contract reverts on 1/DelegateCall) + 20 bytes `to` + 32
 *  bytes `value` + 32 bytes data length + the data itself, back to back with no padding between
 *  calls. Matches packages/contracts/lib/safe-smart-account/src/utils/multisend.ts's own
 *  encodeMetaTransaction exactly. */
function encodeMultiSendCall(to: Address, data: Hex): Hex {
  return encodePacked(["uint8", "address", "uint256", "uint256", "bytes"], [0, to, 0n, BigInt((data.length - 2) / 2), data]);
}

/** Bundles multiple {to, data} calls into the single eth_sendTransaction that sends them all as
 *  one Safe transaction (via MultiSendCallOnly), instead of one eth_sendTransaction per call.
 *  See STEP_TIMEOUT_MESSAGE's sibling doc comment on sendTransaction below for why this replaced
 *  the previous one-request-per-step approach: a real stuck run showed the first request on a
 *  session succeed and every one after it on the same provider silently never reach the wallet,
 *  with no error on either side, even after re-fetching the provider per request. One request
 *  total removes the "every request after the first" failure mode entirely, rather than working
 *  around it. */
export function buildBatchedTransaction(calls: { to: Address; data: Hex }[]): { to: Address; data: Hex } {
  if (calls.length === 1) return calls[0]!;
  const packed = concatHex(calls.map((c) => encodeMultiSendCall(c.to, c.data)));
  return {
    to: MULTISEND_CALL_ONLY_ADDRESS,
    data: encodeFunctionData({ abi: MULTISEND_ABI, functionName: "multiSend", args: [packed] }),
  };
}

const publicClient = createPublicClient({ chain: base, transport: http() });

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
  {
    type: "function",
    name: "buildParamsAttested",
    stateMutability: "view",
    inputs: [{ name: "", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
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

/** The exact `keccak256` Aqua.ship() will key this strategy's ledger entries under -- pure
 *  function of (maker, groups, fee, deviation), no nonce or timestamp anywhere in the encoding.
 *  Aqua.sol's own ship() permanently refuses to ever reuse a strategyHash once shipped
 *  (`StrategiesMustBeImmutable`), even after the strategy was later docked -- docking flips the
 *  ledger entry to a closed marker, it never resets it to shippable. Letting the UI compute this
 *  ahead of signing anything is what makes it possible to check for that collision before
 *  wasting a real signature on a strategy that can never activate. */
export function computeStrategyHash(safeAddress: Address, groups: StrategyGroup[], feeBpsPm: bigint, maxDeviationBpsPm: bigint): Hex {
  const program = buildProgram(toEncodingGroups(groups), feeBpsPm, maxDeviationBpsPm);
  const order = buildOrder(safeAddress, program);
  return keccak256(encodeOrder(order));
}

export type ShipStep =
  | { kind: "approve"; label: string; to: Address; data: Hex; token: Address }
  | { kind: "attest"; label: string; to: Address; data: Hex; strategyHash: Hex }
  | { kind: "ship"; label: string; to: Address; data: Hex };

/** Builds the ordered list of plain transactions that ship a strategy (per-token approve, then
 *  attestBuildParameters, then ship -- matching
 *  packages/contracts/script/ShipTestStrategy.s.sol's own sequence), without sending any of
 *  them. Split out from execution so the UI can render the full step list (what's about to
 *  happen, in what order) before the first signature request, not just one step at a time. */
export function buildShipSteps({
  safeAddress,
  groups,
  feeBpsPm,
  maxDeviationBpsPm,
  balances,
  tokenSymbols,
}: {
  safeAddress: Address;
  groups: StrategyGroup[];
  feeBpsPm: bigint;
  maxDeviationBpsPm: bigint;
  balances: Record<Address, bigint>;
  /** Address -> symbol, for readable step labels only -- never fed into the on-chain encoding. */
  tokenSymbols: Record<Address, string>;
}): ShipStep[] {
  const encodingGroups = toEncodingGroups(groups);
  const program = buildProgram(encodingGroups, feeBpsPm, maxDeviationBpsPm);
  const order = buildOrder(safeAddress, program);
  const encodedOrder = encodeOrder(order);
  const strategyHash = computeStrategyHash(safeAddress, groups, feeBpsPm, maxDeviationBpsPm);

  const tokens = groups.flatMap((g) => g.tokenAddresses);
  const uniqueTokens = [...new Set(tokens)];
  const amounts = tokens.map((t) => balances[t] ?? 0n);
  const groupNames = groups.map((g) => g.name);

  return [
    ...uniqueTokens.map(
      (token): ShipStep => ({
        kind: "approve",
        label: `Approve ${tokenSymbols[token] ?? token}`,
        to: token,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [AQUA_ADDRESS, maxUint256] }),
        token,
      }),
    ),
    {
      kind: "attest",
      label: "Confirm strategy parameters",
      to: PM_STRATEGY_VALIDATOR_ADDRESS,
      data: encodeFunctionData({
        abi: VALIDATOR_ABI,
        functionName: "attestBuildParameters",
        args: [order, tokens, groupNames],
      }),
      strategyHash,
    },
    {
      kind: "ship",
      label: "Activate the strategy",
      to: AQUA_ADDRESS,
      data: encodeFunctionData({
        abi: AQUA_ABI,
        functionName: "ship",
        args: [PM_ROUTER_ADDRESS, encodedOrder, tokens, amounts],
      }),
    },
  ];
}

/** Checks on-chain whether a step has already gone through -- so retrying after a partial failure
 *  (e.g. one approval succeeded, a later step failed) doesn't ask the wallet to redundantly
 *  reconfirm something already done. No check exists yet for the final "ship" step (Aqua.ship()
 *  only does internal bookkeeping additions, with no simple boolean to read back), so that one
 *  always sends -- acceptable since it's always the very last step. */
export async function isStepAlreadyDone(step: ShipStep, safeAddress: Address): Promise<boolean> {
  if (step.kind === "approve") {
    const allowance = await publicClient.readContract({
      address: step.token,
      abi: erc20Abi,
      functionName: "allowance",
      args: [safeAddress, AQUA_ADDRESS],
    });
    return allowance > 0n;
  }
  if (step.kind === "attest") {
    return publicClient.readContract({
      address: PM_STRATEGY_VALIDATOR_ADDRESS,
      abi: VALIDATOR_ABI,
      functionName: "buildParamsAttested",
      args: [step.strategyHash],
    });
  }
  return false;
}

/** Sends one already-built {to, data} as an ordinary eth_sendTransaction call through the
 *  connected wallet -- the same request shape any dApp sends to any wallet. A connected
 *  Safe{Wallet} session turns it into a normal multisig confirmation on its own, the same way it
 *  would for any other dApp's transaction request.
 *
 *  This app previously tried building a batch by hand-crafting a Safe signature and submitting it
 *  directly to Safe's own backend (via @safe-global/protocol-kit + api-kit). That failed
 *  repeatedly and unpredictably over a WalletConnect-connected session -- the signature
 *  Safe{Wallet} returned was never valid by Safe's own server-side check. buildBatchedTransaction
 *  avoids that entirely: it still produces one plain {to, data} pair (a MultiSendCallOnly call),
 *  sent through this exact same, already-proven eth_sendTransaction path -- Safe{Wallet} signs
 *  and executes it exactly like any other transaction, nothing hand-crafted or submitted
 *  out-of-band. */
export async function sendTransaction(
  to: Address,
  data: Hex,
  safeAddress: Address,
  provider: { request: (args: { method: string; params?: unknown[] | object }) => Promise<unknown> },
): Promise<Hex> {
  return (await withTimeout(
    provider.request({
      method: "eth_sendTransaction",
      params: [{ from: safeAddress, to, data, value: "0x0" }],
    }),
    STEP_TIMEOUT_MS,
    STEP_TIMEOUT_MESSAGE,
  )) as Hex;
}
