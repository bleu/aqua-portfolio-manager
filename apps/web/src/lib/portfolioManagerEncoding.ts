import { concatHex, decodeAbiParameters, encodeAbiParameters, hexToNumber, numberToHex, size, slice, type Address, type Hex } from "viem";

/** Byte-for-byte TypeScript port of packages/contracts/src/utils/PortfolioManagerArgsCodec.sol's
 *  build() and packages/contracts/src/utils/PortfolioManagerProgramBuilder.sol's build() --
 *  there is no JS/TS SDK for @1inch/swap-vm or this repo's own contracts, so this is hand-ported
 *  from the Solidity source, not generated. Verified byte-identical against the real Solidity
 *  output for representative inputs by apps/web/src/lib/portfolioManagerEncoding.test.ts (see
 *  that file and packages/contracts/test/PortfolioManagerEncodingGoldenVectors.t.sol for how the
 *  golden vectors were produced). Change this file and those two together. */

/** Matches SwapVM's fee scale: 1e9 = 100%. One conventional basis point is 100_000. */
export const PM_BPS = 1_000_000_000n;
/** Floor on the LP-configured curve fee, PM_BPS-scaled: 0.5%. Matches
 *  PortfolioManagerArgsCodec.MIN_FEE_BPS -- a lower value reverts on-chain. */
export const MIN_FEE_BPS = 5_000_000n;
const WAD = 1_000_000_000_000_000_000n;

const MIN_GROUPS = 2;
const MAX_GROUPS = 4;
const MAX_MEMBERS_PER_GROUP = 5;

export type Member = {
  /** Index into PortfolioManagerTokenRegistry. Never 0. */
  tokenIndex: number;
  /** Index into PortfolioManagerFeedRegistry. 0 designates this member its group's own numeraire. */
  feedIndex: number;
};

export type Group = {
  /** WAD-scaled (1e18 = 100%). All groups' weights must sum to exactly WAD. */
  weightWad: bigint;
  members: Member[];
};

function floorDiv(a: bigint, b: bigint, c: bigint): bigint {
  return (a * b) / c;
}

function requireArgs(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

/** Port of PortfolioManagerArgsCodec.build(groups, feeBps, maxDeviationBps, bridges=[]). Bridges
 *  are omitted -- the wizard doesn't support cross-unit groups yet, matching ADR-0017's "omit the
 *  entry entirely for a pair of groups that already share a unit." */
export function buildArgs(groups: Group[], feeBpsPm: bigint, maxDeviationBpsPm: bigint): Hex {
  requireArgs(groups.length > 0, "PortfolioManagerEmptyUniverse");
  requireArgs(groups.length >= MIN_GROUPS, "PortfolioManagerTooFewGroups");
  requireArgs(groups.length <= MAX_GROUPS, "PortfolioManagerTooManyGroups");
  requireArgs(
    feeBpsPm >= MIN_FEE_BPS && feeBpsPm <= PM_BPS,
    `PortfolioManagerFeeBpsOutOfRange(${feeBpsPm})`,
  );

  const parts: Hex[] = [numberToHex(groups.length, { size: 1 })];

  let sum = 0n;
  let compactSum = 0n;
  for (let i = 0; i < groups.length; i++) {
    const g = groups[i]!;
    requireArgs(g.weightWad > 0n, `PortfolioManagerZeroWeight(${i})`);
    requireArgs(g.members.length > 0, `PortfolioManagerEmptyGroup(${i})`);
    requireArgs(g.members.length <= MAX_MEMBERS_PER_GROUP, "PortfolioManagerTooManyMembers");
    sum += g.weightWad;

    const compactWeight =
      i === groups.length - 1
        ? compactSum >= PM_BPS
          ? 0n
          : PM_BPS - compactSum
        : floorDiv(g.weightWad, PM_BPS, WAD);
    compactSum += compactWeight;

    parts.push(numberToHex(compactWeight, { size: 4 }));
    parts.push(numberToHex(g.members.length, { size: 1 }));

    let numeraireCount = 0;
    for (let j = 0; j < g.members.length; j++) {
      const m = g.members[j]!;
      requireArgs(m.tokenIndex !== 0, `PortfolioManagerZeroTokenIndex(${i},${j})`);
      if (m.feedIndex === 0) numeraireCount++;
      parts.push(numberToHex(m.tokenIndex, { size: 2 }));
      parts.push(numberToHex(m.feedIndex, { size: 2 }));
    }
    requireArgs(numeraireCount <= 1, `PortfolioManagerMultipleNumeraireMembers(${i})`);
  }
  requireArgs(sum === WAD, `PortfolioManagerWeightsMustSumToWad(${sum})`);
  requireNoDuplicateTokens(groups);

  // No bridges: a zero-length bridge count byte.
  parts.push(numberToHex(0, { size: 1 }));

  parts.push(numberToHex(feeBpsPm, { size: 4 }));
  parts.push(numberToHex(maxDeviationBpsPm, { size: 4 }));

  const args = concatHex(parts);
  const byteLength = (args.length - 2) / 2;
  requireArgs(byteLength <= 255, `PortfolioManagerArgsTooLarge(${byteLength})`);
  return args;
}

function requireNoDuplicateTokens(groups: Group[]): void {
  const tokenIndices = groups.flatMap((g) => g.members.map((m) => m.tokenIndex));
  for (let i = 0; i < tokenIndices.length; i++) {
    for (let j = i + 1; j < tokenIndices.length; j++) {
      requireArgs(tokenIndices[i] !== tokenIndices[j], `PortfolioManagerDuplicateToken(${tokenIndices[i]})`);
    }
  }
}

/** Port of PortfolioManagerProgramBuilder.build(groups, feeBps, maxDeviationBps). Wire format:
 *  [opcode:1 byte][argsLength:1 byte][args]. CURVE_OPCODE is always 0 -- the curve instruction is
 *  the only opcode this codebase's PortfolioManagerOpcodes registers at index 0. */
export function buildProgram(groups: Group[], feeBpsPm: bigint, maxDeviationBpsPm: bigint): Hex {
  const CURVE_OPCODE = 0;
  const args = buildArgs(groups, feeBpsPm, maxDeviationBpsPm);
  const argsLength = (args.length - 2) / 2;
  requireArgs(argsLength <= 255, `args too large for 1-byte length prefix (${argsLength})`);
  return concatHex([numberToHex(CURVE_OPCODE, { size: 1 }), numberToHex(argsLength, { size: 1 }), args]);
}

export type Order = {
  maker: Address;
  traits: bigint;
  data: Hex;
};

/** Port of MakerTraitsLib.build() for this app's fixed maker-traits configuration: no hooks, no
 *  WETH-unwrap, useAquaInsteadOfSignature=true, receiver=address(0) (matches
 *  packages/contracts/script/ShipTestStrategy.s.sol's own Args). With every hook disabled and no
 *  receiver override, MakerTraitsLib's bit-packing collapses to a single constant bit
 *  (USE_AQUA_INSTEAD_OF_SIGNATURE_BIT_FLAG = 1<<254) ORed with the zero receiver, and `data`
 *  collapses to exactly the program bytes with no hook-slice prefix -- see
 *  packages/contracts/lib/swap-vm/src/libs/MakerTraits.sol for the general-case layout this
 *  specializes. If the wizard ever exposes WETH-unwrap, hooks, or a custom receiver, this needs
 *  the general bit-packing, not this shortcut. */
const USE_AQUA_INSTEAD_OF_SIGNATURE_BIT_FLAG = 1n << 254n;

export function buildOrder(maker: Address, program: Hex): Order {
  return { maker, traits: USE_AQUA_INSTEAD_OF_SIGNATURE_BIT_FLAG, data: program };
}

const ORDER_ABI_PARAM = {
  type: "tuple",
  components: [
    { name: "maker", type: "address" },
    { name: "traits", type: "uint256" },
    { name: "data", type: "bytes" },
  ],
} as const;

/** ABI-encodes the ISwapVM.Order struct for Aqua.ship(router, abi.encode(order), tokens, amounts)
 *  -- plain Solidity ABI encoding (not packed), so viem's standard encoder applies directly. */
export function encodeOrder(order: Order): Hex {
  return encodeAbiParameters([ORDER_ABI_PARAM], [order]);
}

/** The exact reverse of encodeOrder -- decodes the `encodedOrder` bytes the indexer stores
 *  straight from Aqua's own Shipped event (see apps/indexer/ponder.schema.ts's strategy.encodedOrder
 *  doc comment) back into {maker, traits, data}, so a History-page reship can recover the
 *  original strategy's program bytes without needing any local wizard state. */
export function decodeOrder(encodedOrder: Hex): Order {
  const [order] = decodeAbiParameters([ORDER_ABI_PARAM], encodedOrder);
  return order as Order;
}

/** Appends `nonce` to the end of an already-built program's own args section, bumping the
 *  program's own 1-byte argsLength header to match. PortfolioManagerArgsCodec.parse() and
 *  decodeTrusted() (packages/contracts/src/utils/PortfolioManagerArgsCodec.sol) only ever read
 *  fixed offsets through maxDeviationBps and never check those offsets consume the whole args
 *  blob -- confirmed by reading both functions directly, not assumed -- so trailing bytes decode
 *  as if they weren't there: every real field (baskets, tokens, fee, deviation) stays identical,
 *  only the program's raw bytes, and therefore Aqua's strategyHash = keccak256(abi.encode(order)),
 *  change. This is how a History-page reship gets a strategy that is economically identical to
 *  one already docked -- Aqua's own StrategiesMustBeImmutable has no path back to shippable for
 *  the original hash, but a nonce byte makes it a "new" strategy Aqua has never seen. */
export function appendNonceToProgram(program: Hex, nonce: Hex): Hex {
  const opcode = slice(program, 0, 1);
  const argsLength = size(program) - 2;
  const args = slice(program, 2, 2 + argsLength);
  const newArgs = concatHex([args, nonce]);
  const newArgsLength = size(newArgs);
  requireArgs(newArgsLength <= 255, `PortfolioManagerArgsTooLarge(${newArgsLength})`);
  return concatHex([opcode, numberToHex(newArgsLength, { size: 1 }), newArgs]);
}

export type DecodedGroup = {
  /** PM_BPS-scaled (1e9 = 100%) -- the exact target share buildArgs encoded for this group. */
  weightBps: number;
  /** PortfolioManagerTokenRegistry indices, in encoded order. Resolve with tokenFeeds.ts's
   *  tokenAtRegistryIndex -- never re-derive a registry index any other way (see that function's
   *  own doc comment for why its 1-based-position mapping is the real one). */
  tokenIndices: number[];
};

/** Shared by decodeGroups and decodeArgs -- walks the group section once, handing back both the
 *  decoded groups and the byte offset right after them (where bridges/fee/deviation start), so a
 *  caller that needs those doesn't have to re-walk the groups to find where they begin. Mirrors
 *  PortfolioManagerArgsCodec.parse()'s exact byte layout: groupCount(1) + per group:
 *  compactWeight(4, PM_BPS-scaled) + memberCount(1) + per member: tokenIndex(2) + feedIndex(2) --
 *  feedIndex is read past, not decoded, since nothing here needs it. */
function decodeGroupsWithOffset(args: Hex): { groups: DecodedGroup[]; offset: number } {
  const groupCount = hexToNumber(slice(args, 0, 1));
  const groups: DecodedGroup[] = [];
  let offset = 1;
  for (let i = 0; i < groupCount; i++) {
    const weightBps = hexToNumber(slice(args, offset, offset + 4));
    const memberCount = hexToNumber(slice(args, offset + 4, offset + 5));
    offset += 5;
    const tokenIndices: number[] = [];
    for (let j = 0; j < memberCount; j++) {
      tokenIndices.push(hexToNumber(slice(args, offset, offset + 2)));
      offset += 4; // tokenIndex (2 bytes, just read) + feedIndex (2 bytes, skipped)
    }
    groups.push({ weightBps, tokenIndices });
  }
  return { groups, offset };
}

/** Reverse of buildArgs' own group-encoding section only -- stops before bridges/fee/deviation.
 *  Use decodeArgs instead when the fee or deviation limit is needed too. */
export function decodeGroups(args: Hex): DecodedGroup[] {
  return decodeGroupsWithOffset(args).groups;
}

export type DecodedStrategyParameters = {
  groups: DecodedGroup[];
  /** PM_BPS-scaled (1e9 = 100%) LP curve fee. Divide by 1e7 for a plain percentage -- the exact
   *  reverse of safeProposal.ts's own `BigInt(Math.round(lpFeePct * 1e7))` encoding. */
  feeBps: number;
  /** PM_BPS-scaled (1e9 = 100%) price-deviation circuit breaker limit, same 1e7-per-percent scale
   *  as feeBps. Zero disables the check entirely (PortfolioManagerArgsCodec.sol). */
  maxDeviationBps: number;
};

/** Full reverse of buildArgs: groups, then skips past any bridge entries (groupA(1) + groupB(1) +
 *  feed(20) + maxStaleness(3) = 25 bytes each -- bridge content itself isn't decoded, nothing here
 *  needs it) straight to feeBps(4) and maxDeviationBps(4), the two trailing words buildArgs always
 *  writes last. */
export function decodeArgs(args: Hex): DecodedStrategyParameters {
  const { groups, offset: afterGroups } = decodeGroupsWithOffset(args);
  const bridgeCount = hexToNumber(slice(args, afterGroups, afterGroups + 1));
  const afterBridges = afterGroups + 1 + bridgeCount * 25;
  const feeBps = hexToNumber(slice(args, afterBridges, afterBridges + 4));
  const maxDeviationBps = hexToNumber(slice(args, afterBridges + 4, afterBridges + 8));
  return { groups, feeBps, maxDeviationBps };
}

/** The args section of a program (opcode(1) + argsLength(1) + args) -- the same slice
 *  appendNonceToProgram itself extracts before appending to it. */
function programArgs(program: Hex): Hex {
  return slice(program, 2, size(program));
}

/** True if `childEncodedOrder` is exactly what reshipping `parentEncodedOrder` produces (see
 *  buildReshipSteps in safeProposal.ts): same maker, same traits, same opcode, and its args are
 *  the parent's own args with a trailing nonce appendNonceToProgram tacked on -- not the whole
 *  program byte-for-byte, since appendNonceToProgram also rewrites the 1-byte argsLength header
 *  that precedes them. Aqua has no "reshipped from" relationship of its own -- a reship is,
 *  correctly, a genuinely different strategyHash -- so this is the only way to recover that
 *  lineage afterward: by comparing the real bytes the two strategies actually ran with, not
 *  something either side declared. Works for a reship chain of any length (each one 8 bytes
 *  longer than the last) and for a reship built by any client, not just this app's own
 *  buildReshipSteps. */
export function isReshipOf(childEncodedOrder: Hex, parentEncodedOrder: Hex): boolean {
  const child = decodeOrder(childEncodedOrder);
  const parent = decodeOrder(parentEncodedOrder);
  if (child.maker.toLowerCase() !== parent.maker.toLowerCase() || child.traits !== parent.traits) return false;
  if (slice(child.data, 0, 1) !== slice(parent.data, 0, 1)) return false;

  const childArgs = programArgs(child.data);
  const parentArgs = programArgs(parent.data);
  if (size(childArgs) <= size(parentArgs)) return false;
  return childArgs.toLowerCase().startsWith(parentArgs.toLowerCase());
}

/** The program's real byte length -- NOT encodedOrder's own hex-string length, which can be
 *  identical for two strategies whose padded abi-encoding happens to round up to the same 32-byte
 *  slot. Confirmed on real data: a reship whose nonce still fits the same padding boundary as its
 *  parent produces an encodedOrder string of the exact same length, even though the real decoded
 *  program is genuinely longer. Callers ordering a reship chain by generation (closest parent
 *  first) need this, not encodedOrder.length. */
export function programByteLength(encodedOrder: Hex): number {
  return size(decodeOrder(encodedOrder).data);
}

/** Decodes an indexer-stored Strategy.encodedOrder straight into its basket groups -- everything
 *  the dashboard needs for real per-basket target shares, independent of any local wizard draft
 *  (see activeStrategyStorage.ts's own doc comment for why that snapshot can't be trusted: it's
 *  wiped on dock and was never written at all for a strategy shipped outside the wizard). */
export function decodeOrderGroups(encodedOrder: Hex): DecodedGroup[] {
  const order = decodeOrder(encodedOrder);
  const argsLength = size(order.data) - 2;
  const args = slice(order.data, 2, 2 + argsLength);
  return decodeGroups(args);
}

/** Same source as decodeOrderGroups, but also decodes the LP fee and the max price-deviation
 *  limit -- for a History card showing the strategy's real parameters, not just its baskets. */
export function decodeOrderParameters(encodedOrder: Hex): DecodedStrategyParameters {
  return decodeArgs(programArgs(decodeOrder(encodedOrder).data));
}
