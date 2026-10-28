import SafeAppsSDK from "@safe-global/safe-apps-sdk";
import {
  createPublicClient,
  createWalletClient,
  custom,
  encodeFunctionData,
  erc20Abi,
  getAddress,
  http,
  keccak256,
  maxUint256,
  toHex,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import { getCapabilities, sendCalls, waitForCallsStatus } from "viem/actions";
import { base } from "wagmi/chains";
import { AQUA_ADDRESS, PM_BASKET_SCOPE_GUARD_FACTORY_ADDRESS, PM_ROUTER_ADDRESS, PM_STRATEGY_VALIDATOR_ADDRESS } from "./contracts";
import { appendNonceToProgram, buildOrder, buildProgram, decodeOrder, encodeOrder, type Group, type Order } from "./portfolioManagerEncoding";
import { getRegistryIndex } from "./tokenFeeds";

export type EIP1193Provider = { request: (args: { method: string; params?: unknown[] | object }) => Promise<unknown> };

const publicClient = createPublicClient({ chain: base, transport: http() });

/** A single step's own round trip through the wallet (mobile push notification, user action,
 *  response) can take a while -- generous, but still bounded per step, so a stalled step can't
 *  freeze the whole multi-step flow forever. Applied per eth_sendTransaction call, not once for
 *  the whole sequence, since that sequence can now be several steps long. */
const STEP_TIMEOUT_MS = 90_000;
export const STEP_TIMEOUT_MESSAGE = "__aqua_pm_create_transaction_step_timeout__";

/** confirmAtomicBatch's own wait is a different kind from STEP_TIMEOUT_MS above: not "how long
 *  until a human responds to a wallet prompt" (the user already responded by the time a bundle id
 *  comes back from requestAtomicBatch), but "how long until the batch is mined on Base and
 *  Safe{Wallet}'s own backend has indexed and reported it back" -- real-world confirmed to
 *  regularly exceed 90 seconds even for an already-successful transaction, which previously
 *  surfaced as a false "something went wrong" error on a strategy that had, in fact, shipped. */
const BATCH_CONFIRMATION_TIMEOUT_MS = 5 * 60_000;

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

const GUARD_FACTORY_ABI = [
  {
    type: "function",
    name: "computeAddress",
    stateMutability: "view",
    inputs: [
      { name: "aqua", type: "address" },
      { name: "safe_", type: "address" },
      { name: "trustedPmStrategyHash", type: "bytes32" },
      { name: "trustedPmRouter", type: "address" },
      { name: "tokens", type: "address[]" },
      { name: "basketIds", type: "uint256[]" },
    ],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "deploy",
    stateMutability: "nonpayable",
    inputs: [
      { name: "aqua", type: "address" },
      { name: "safe_", type: "address" },
      { name: "trustedPmStrategyHash", type: "bytes32" },
      { name: "trustedPmRouter", type: "address" },
      { name: "tokens", type: "address[]" },
      { name: "basketIds", type: "uint256[]" },
    ],
    outputs: [{ name: "guard", type: "address" }],
  },
] as const;

const SAFE_GUARD_ABI = [
  {
    type: "function",
    name: "setGuard",
    stateMutability: "nonpayable",
    inputs: [{ name: "guard", type: "address" }],
    outputs: [],
  },
] as const;

/** keccak256("guard_manager.guard.address") -- the exact slot Safe's own GuardManager.sol reads
 *  and writes via raw sstore/sload, confirmed against the vendored
 *  lib/safe-smart-account/contracts/base/GuardManager.sol rather than assumed, since Safe only
 *  exposes this through StorageAccessible.getStorageAt, never a plain public getter. */
const GUARD_STORAGE_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8" as Hex;

/** Reads whatever guard is actually installed on a Safe right now, straight from
 *  GUARD_STORAGE_SLOT -- zeroAddress if none. Shared by isStepAlreadyDone's own "setGuard" check
 *  below and by the dock flow's decision to skip asking for a pointless signature when there's
 *  no guard to remove (see dockProposal.ts's own buildRemoveGuardTransaction). */
export async function readInstalledGuard(safeAddress: Address): Promise<Address> {
  const stored = await publicClient.getStorageAt({ address: safeAddress, slot: GUARD_STORAGE_SLOT });
  if (!stored) return zeroAddress;
  // getStorageAt returns the full 32-byte word; an address occupies its low 20 bytes.
  return getAddress(`0x${stored.slice(-40)}`);
}

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
  | { kind: "ship"; label: string; to: Address; data: Hex }
  | { kind: "deployGuard"; label: string; to: Address; data: Hex; guardAddress: Address }
  | { kind: "setGuard"; label: string; to: Address; data: Hex; guardAddress: Address };

/** basketId 0 is reserved (BasketScopeGuard.sol's constructor rejects it), so the first group
 *  gets 1 -- flattens each group's own tokens against that same id, matching the parallel
 *  tokens[]/basketIds[] shape BasketScopeGuard's constructor and BasketScopeGuardFactory's
 *  deploy/computeAddress both expect. */
function toBasketScopeTokensAndIds(groups: StrategyGroup[]): { tokens: Address[]; basketIds: bigint[] } {
  const tokens: Address[] = [];
  const basketIds: bigint[] = [];
  groups.forEach((group, i) => {
    const basketId = BigInt(i + 1);
    for (const token of group.tokenAddresses) {
      tokens.push(token);
      basketIds.push(basketId);
    }
  });
  return { tokens, basketIds };
}

/** Builds the ordered list of plain transactions that ship a strategy (per-token approve, then
 *  attestBuildParameters, then ship -- matching
 *  packages/contracts/script/ShipTestStrategy.s.sol's own sequence), without sending any of
 *  them. Split out from execution so the UI can render the full step list (what's about to
 *  happen, in what order) before the first signature request, not just one step at a time.
 *
 *  Appends two more steps -- deploy the strategy's own BasketScopeGuard, then install it on the
 *  Safe -- whenever PM_BASKET_SCOPE_GUARD_FACTORY_ADDRESS is configured (see that constant's own
 *  doc comment for why it's optional). Guard installation doesn't need ship() to have run first
 *  (the Guard only ever reads the strategy hash/router/basket mapping, never Aqua's ledger), so
 *  it's safe to always place these last: the strategy activates, then every future transaction on
 *  this Safe is protected against shipping a different strategy across these same baskets. */
export async function buildShipSteps({
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
}): Promise<ShipStep[]> {
  const encodingGroups = toEncodingGroups(groups);
  const program = buildProgram(encodingGroups, feeBpsPm, maxDeviationBpsPm);
  const order = buildOrder(safeAddress, program);
  const encodedOrder = encodeOrder(order);
  const strategyHash = computeStrategyHash(safeAddress, groups, feeBpsPm, maxDeviationBpsPm);

  const tokens = groups.flatMap((g) => g.tokenAddresses);
  const uniqueTokens = [...new Set(tokens)];
  const amounts = tokens.map((t) => balances[t] ?? 0n);
  const groupNames = groups.map((g) => g.name);

  const steps: ShipStep[] = [
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

  if (PM_BASKET_SCOPE_GUARD_FACTORY_ADDRESS) {
    const { tokens: guardTokens, basketIds: guardBasketIds } = toBasketScopeTokensAndIds(groups);
    const guardArgs = [AQUA_ADDRESS, safeAddress, strategyHash, PM_ROUTER_ADDRESS, guardTokens, guardBasketIds] as const;
    const guardAddress = await publicClient.readContract({
      address: PM_BASKET_SCOPE_GUARD_FACTORY_ADDRESS,
      abi: GUARD_FACTORY_ABI,
      functionName: "computeAddress",
      args: guardArgs,
    });

    steps.push({
      kind: "deployGuard",
      label: "Deploy this strategy's guard",
      to: PM_BASKET_SCOPE_GUARD_FACTORY_ADDRESS,
      data: encodeFunctionData({ abi: GUARD_FACTORY_ABI, functionName: "deploy", args: guardArgs }),
      guardAddress,
    });
    steps.push({
      kind: "setGuard",
      label: "Protect the Safe with the guard",
      to: safeAddress,
      data: encodeFunctionData({ abi: SAFE_GUARD_ABI, functionName: "setGuard", args: [guardAddress] }),
      guardAddress,
    });
  }

  return steps;
}

/** Builds the steps that reship an exact copy of a strategy this Safe already docked --
 *  approve + attest + ship only, sourced entirely from the indexer's own StrategyHistoryEntry
 *  (encodedOrder, tokens, groupNames), not local wizard drafts -- those are a best-effort, per-
 *  Safe snapshot that's wiped the moment a strategy is docked (see activeStrategyStorage.ts's own
 *  doc comment), so they can't be trusted for a strategy that might be several dockings old or
 *  shipped from a different device entirely. Only the program's trailing bytes change (see
 *  appendNonceToProgram's own doc comment for why that's enough to get a fresh, shippable
 *  strategyHash) -- every real field decodes identically, so this is genuinely the same strategy.
 *
 *  Deliberately does not add deployGuard/setGuard steps the way buildShipSteps does: building the
 *  Guard's tokens[]/basketIds[] correctly needs the original basket *boundaries* (which token
 *  belonged to which group), and the indexer only stores the flat, already-shipped token list,
 *  not that grouping. Guessing at a grouping (e.g. one basket with everything) would produce a
 *  Guard that looks protective but doesn't actually block anything -- worse than no Guard, since
 *  it'd look like protection that isn't there. */
export async function buildReshipSteps({
  encodedOrder,
  tokens,
  groupNames,
  balances,
  tokenSymbols,
}: {
  /** The exact bytes Aqua emitted for the strategy being reshipped (StrategyHistoryEntry.encodedOrder)
   *  -- already carries the maker (this Safe's own address, by construction of the indexer query
   *  that produced it), so no separate safeAddress param is needed here. */
  encodedOrder: Hex;
  tokens: Address[];
  groupNames: string[] | null;
  balances: Record<Address, bigint>;
  tokenSymbols: Record<Address, string>;
}): Promise<ShipStep[]> {
  const original = decodeOrder(encodedOrder);
  const nonce = toHex(crypto.getRandomValues(new Uint8Array(8)));
  const newOrder: Order = { ...original, data: appendNonceToProgram(original.data, nonce) };
  const newEncodedOrder = encodeOrder(newOrder);
  const strategyHash = keccak256(newEncodedOrder);

  const uniqueTokens = [...new Set(tokens)];
  const amounts = tokens.map((t) => balances[t] ?? 0n);

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
        args: [newOrder, tokens, groupNames ?? []],
      }),
      strategyHash,
    },
    {
      kind: "ship",
      label: "Reactivate the strategy",
      to: AQUA_ADDRESS,
      data: encodeFunctionData({
        abi: AQUA_ABI,
        functionName: "ship",
        args: [PM_ROUTER_ADDRESS, newEncodedOrder, tokens, amounts],
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
  if (step.kind === "deployGuard") {
    const code = await publicClient.getCode({ address: step.guardAddress });
    return !!code && code !== "0x";
  }
  if (step.kind === "setGuard") {
    const installedGuard = await readInstalledGuard(safeAddress);
    return installedGuard === step.guardAddress;
  }
  return false;
}

/** Sends one already-built {to, data} as an ordinary eth_sendTransaction call through the
 *  connected wallet -- the same request shape any dApp sends to any wallet. A connected
 *  Safe{Wallet} session turns it into a normal multisig confirmation on its own, the same way it
 *  would for any other dApp's transaction request.
 *
 *  Used for every step when connected over WalletConnect: plain eth_sendTransaction has no way to
 *  mark a call as a Safe "batch" (there is no operation field in the standard request), so each
 *  step the Safe executes this way runs as its own top-level Call, with the Safe itself as
 *  msg.sender -- correct, just one signature per step. See sendTransactionsViaSafeAppsSdk's own
 *  doc comment for why a batch of these can't just be wrapped in MultiSendCallOnly and sent as one
 *  such call instead (that was tried and shipped a real, confirmed-on-chain bug: BLEUDEV
 *  investigation found the resulting Shipped event's maker was MultiSendCallOnly's own address,
 *  not the Safe's, because the Safe only *called* it instead of delegating into it). */
export async function sendTransaction(to: Address, data: Hex, safeAddress: Address, provider: EIP1193Provider): Promise<Hex> {
  return (await withTimeout(
    provider.request({
      method: "eth_sendTransaction",
      params: [{ from: safeAddress, to, data, value: "0x0" }],
    }),
    STEP_TIMEOUT_MS,
    STEP_TIMEOUT_MESSAGE,
  )) as Hex;
}

/** Sends multiple calls as one real Safe batch transaction, via the Safe Apps SDK's own
 *  `txs.send` -- only reachable when this page is embedded inside Safe{Wallet} as a Safe App (the
 *  wagmi `safe` connector), since the SDK talks to the parent Safe{Wallet} window directly over
 *  postMessage, not through any wallet-generic RPC method.
 *
 *  This replaced a hand-rolled approach that packed every call into one MultiSendCallOnly
 *  `multiSend(bytes)` payload and sent it as a single plain eth_sendTransaction. That looked
 *  correct (real round-trip-decoded against the real contract) but had a bug standard
 *  eth_sendTransaction can never avoid: it has no field to request Safe's DelegateCall operation,
 *  so Safe{Wallet} proposed it as a plain Call -- which makes MultiSendCallOnly itself the caller
 *  of every inner call, not the Safe. Confirmed directly on a real shipped strategy: the resulting
 *  `Aqua.Shipped` event's `maker` was MultiSendCallOnly's own address, not the Safe's, silently
 *  orphaning the strategy (no funds lost -- ship() only authorizes, never moves tokens -- but the
 *  strategy was unreachable by `dock()` or any swap, since both key off the Safe's own address).
 *  `txs.send` doesn't have this gap: Safe{Wallet} itself constructs the batch, the same trusted
 *  path its own UI uses for its own batching feature, so it sets the right operation internally. */
export async function sendTransactionsViaSafeAppsSdk(calls: { to: Address; data: Hex }[]): Promise<Hex> {
  const sdk = new SafeAppsSDK();
  const { safeTxHash } = await sdk.txs.send({
    txs: calls.map(({ to, data }) => ({ to, value: "0", data })),
  });
  return safeTxHash as Hex;
}

/** True when the connected wallet declares atomic-batch support for Base via EIP-5792's
 *  wallet_getCapabilities. As of 2026-10, Safe{Wallet} is the only wallet confirmed to support
 *  wallet_sendCalls over WalletConnect -- this checks live rather than assuming, so every other
 *  wallet (and a Safe{Wallet} version that hasn't shipped it yet) falls straight through to
 *  sendCallsViaEip5792's caller using the one-call-per-step path instead. */
export async function supportsAtomicBatch(safeAddress: Address, provider: EIP1193Provider): Promise<boolean> {
  try {
    const client = createWalletClient({ chain: base, transport: custom(provider) });
    const capabilities = await getCapabilities(client, { account: safeAddress, chainId: base.id });
    const status = (capabilities as { atomic?: { status?: string } } | undefined)?.atomic?.status;
    return status === "supported" || status === "ready";
  } catch {
    return false;
  }
}

/** Requests an atomic batch via EIP-5792's wallet_sendCalls -- the WalletConnect-reachable
 *  equivalent of sendTransactionsViaSafeAppsSdk above, for a wallet that supportsAtomicBatch
 *  already confirmed supports it. Crucially, this doesn't have that function's replaced
 *  MultiSendCallOnly bug: the *wallet* decides how to execute the batch atomically (Safe can
 *  choose DelegateCall internally, the same way its own UI's own batching feature does), so
 *  msg.sender for every inner call is still the Safe, not an intermediary.
 *
 *  Split from confirmAtomicBatch below so the caller can fall back to per-step sending if *this*
 *  call fails (a wallet mishandling the method entirely -- Safe's own GitHub has open issues
 *  about spec-version drift here -- fails before anything executes, which atomicRequired
 *  guarantees), while treating a confirmAtomicBatch failure as real: once a bundle id comes back
 *  the batch is already in flight, and retrying per-step at that point could double-send. */
export async function requestAtomicBatch(
  calls: { to: Address; data: Hex }[],
  safeAddress: Address,
  provider: EIP1193Provider,
): Promise<{ id: string }> {
  const client = createWalletClient({ chain: base, transport: custom(provider) });
  return withTimeout(
    sendCalls(client, { account: safeAddress, calls: calls.map(({ to, data }) => ({ to, data })), forceAtomic: true }),
    STEP_TIMEOUT_MS,
    STEP_TIMEOUT_MESSAGE,
  );
}

/** Waits for the batch requestAtomicBatch started and returns its real transaction hash. See
 *  requestAtomicBatch's own doc comment for why a failure here must not be retried per-step. */
export async function confirmAtomicBatch(id: string, provider: EIP1193Provider): Promise<Hex> {
  const client = createWalletClient({ chain: base, transport: custom(provider) });
  const { receipts, status } = await waitForCallsStatus(client, { id, timeout: BATCH_CONFIRMATION_TIMEOUT_MS });
  const transactionHash = receipts?.[0]?.transactionHash;
  if (status !== "success" || !transactionHash) {
    throw new Error(`EIP-5792 batch did not succeed (status: ${status ?? "unknown"})`);
  }
  return transactionHash;
}

export type ShipConnector = { id: string; getProvider: () => Promise<unknown> };

/** Sends every step not already done, through whichever path the connected wallet supports --
 *  Safe App batch, EIP-5792 atomic batch, or one eth_sendTransaction per step, falling back in
 *  that order exactly the way the ship wizard's review page originally did inline. Extracted here
 *  so a second flow (the History page's reship action) doesn't have to re-derive this branching
 *  and risk reintroducing the real bug sendTransactionsViaSafeAppsSdk's own doc comment describes
 *  (a hand-rolled MultiSendCallOnly batch making it the maker instead of the Safe).
 *  `onStepStatus` is optional -- a caller that doesn't render a per-step list can omit it. */
export async function executeShipSteps({
  steps,
  safeAddress,
  connector,
  onStepStatus,
}: {
  steps: ShipStep[];
  safeAddress: Address;
  connector: ShipConnector;
  onStepStatus?: (index: number, status: "done" | "active" | "error") => void;
}): Promise<Address | undefined> {
  const remaining: { index: number; step: ShipStep }[] = [];
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]!;
    if (await isStepAlreadyDone(step, safeAddress)) {
      onStepStatus?.(i, "done");
    } else {
      remaining.push({ index: i, step });
    }
  }

  let txHash: Address | undefined;
  if (remaining.length > 0 && connector.id === "safe") {
    // Embedded as a Safe App: one real Safe batch via the Safe Apps SDK, which Safe{Wallet}
    // itself constructs (and correctly delegates into) -- see sendTransactionsViaSafeAppsSdk's
    // own doc comment for why this replaced packing calls into MultiSendCallOnly by hand.
    remaining.forEach(({ index }) => onStepStatus?.(index, "active"));
    try {
      txHash = await sendTransactionsViaSafeAppsSdk(remaining.map(({ step }) => ({ to: step.to, data: step.data })));
    } catch (stepErr) {
      remaining.forEach(({ index }) => onStepStatus?.(index, "error"));
      throw stepErr;
    }
    remaining.forEach(({ index }) => onStepStatus?.(index, "done"));
  } else if (remaining.length > 0) {
    // Any other connector (WalletConnect): plain eth_sendTransaction has no way to ask Safe to
    // batch, but a wallet that declares EIP-5792 support (confirmed so far: only Safe{Wallet},
    // see supportsAtomicBatch's own doc comment) can still batch atomically via wallet_sendCalls.
    // Falls back to one eth_sendTransaction per step for any wallet that doesn't report support,
    // or whose wallet_sendCalls request itself fails (not a later confirmation failure -- see
    // requestAtomicBatch's own doc comment for why).
    const provider = (await connector.getProvider()) as EIP1193Provider;
    const calls = remaining.map(({ step }) => ({ to: step.to, data: step.data }));

    let batchId: string | undefined;
    if (remaining.length > 1 && (await supportsAtomicBatch(safeAddress, provider))) {
      try {
        ({ id: batchId } = await requestAtomicBatch(calls, safeAddress, provider));
      } catch {
        batchId = undefined; // Falls through to the per-step loop below.
      }
    }

    if (batchId) {
      remaining.forEach(({ index }) => onStepStatus?.(index, "active"));
      try {
        txHash = await confirmAtomicBatch(batchId, provider);
      } catch (stepErr) {
        remaining.forEach(({ index }) => onStepStatus?.(index, "error"));
        throw stepErr;
      }
      remaining.forEach(({ index }) => onStepStatus?.(index, "done"));
    } else {
      for (const { index, step } of remaining) {
        onStepStatus?.(index, "active");
        try {
          txHash = await sendTransaction(step.to, step.data, safeAddress, provider);
        } catch (stepErr) {
          onStepStatus?.(index, "error");
          throw stepErr;
        }
        onStepStatus?.(index, "done");
      }
    }
  }

  return txHash;
}
