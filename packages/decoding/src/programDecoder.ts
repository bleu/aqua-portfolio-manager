import { slice, size, type Address, type Hex } from "viem";

export interface DecodedMember {
  token: Address;
  feed: Address;
  maxStaleness: number;
}

export interface DecodedGroup {
  weightWad: bigint;
  members: DecodedMember[];
}

export interface DecodedProgram {
  groups: DecodedGroup[];
  feeBps: number;
  maxDeviationBps: number;
  /// Present only when the program includes the resolver KYC gate opcode (see ADR-0015) --
  /// undefined for a strategy built with the plain, ungated builder.
  resolverKycToken: Address | undefined;
}

export class ProgramDecodeError extends Error {}

const CURVE_OPCODE = 0;
const KYC_GATE_OPCODE = 1;
/// Matches PortfolioManagerArgsCodec.sol's own private constants exactly -- see that file's
/// GROUP_HEADER_SIZE/MEMBER_ENTRY_SIZE doc comments for the byte-layout rationale.
const GROUP_HEADER_SIZE = 17; // 16-byte weight + 1-byte member count
const MEMBER_ENTRY_SIZE = 42; // 20-byte token + 20-byte feed + 2-byte maxStaleness

function readUint8(program: Hex, offset: number): number {
  return Number(BigInt(slice(program, offset, offset + 1)));
}

function readUint16(program: Hex, offset: number): number {
  return Number(BigInt(slice(program, offset, offset + 2)));
}

function readUint32(program: Hex, offset: number): number {
  return Number(BigInt(slice(program, offset, offset + 4)));
}

function readUint128(program: Hex, offset: number): bigint {
  return BigInt(slice(program, offset, offset + 16));
}

function readAddress(program: Hex, offset: number): Address {
  return slice(program, offset, offset + 20) as Address;
}

/// Decodes curve args starting at `offset` (right after the curve instruction's own
/// [opcode][argsLength] header) -- mirrors PortfolioManagerArgsCodec.sol's `decodeTrusted`
/// exactly, byte for byte. Returns the offset just past the decoded args, for the caller to
/// continue reading any instruction after the curve one.
function decodeCurveArgs(program: Hex, offset: number): { groups: DecodedGroup[]; feeBps: number; maxDeviationBps: number; end: number } {
  const groupCount = readUint8(program, offset);
  offset += 1;

  const groups: DecodedGroup[] = [];
  for (let i = 0; i < groupCount; i++) {
    const weightWad = readUint128(program, offset);
    const memberCount = readUint8(program, offset + 16);
    offset += GROUP_HEADER_SIZE;

    const members: DecodedMember[] = [];
    for (let j = 0; j < memberCount; j++) {
      const token = readAddress(program, offset);
      const feed = readAddress(program, offset + 20);
      const maxStaleness = readUint16(program, offset + 40);
      members.push({ token, feed, maxStaleness });
      offset += MEMBER_ENTRY_SIZE;
    }
    groups.push({ weightWad, members });
  }

  const feeBps = readUint32(program, offset);
  offset += 4;
  const maxDeviationBps = readUint32(program, offset);
  offset += 4;

  return { groups, feeBps, maxDeviationBps, end: offset };
}

/// Decodes a full PM strategy program (the `strategy` bytes Aqua's `Shipped` event carries,
/// mirrored into `strategies.program` by the sync-indexer job): the curve instruction
/// (`PortfolioManagerProgramBuilder`'s or `GatedPortfolioManagerProgramBuilder`'s wire format --
/// see ADR-0015), plus the resolver KYC gate instruction when present.
///
/// Trusts the bytes the way `decodeTrusted` does on-chain: PM only ever reads a program after
/// `PortfolioManagerStrategyValidator.attestBuildParameters` already validated it (ADR-0013), so
/// this doesn't re-derive every one of that validator's checks -- it throws `ProgramDecodeError`
/// on a structurally short/malformed program (can't read past the end), not on a
/// business-rule violation (duplicate token, weights not summing to WAD, etc.) that on-chain
/// attestation already prevents for any strategy actually reachable from `Shipped`.
export function decodeProgram(program: Hex): DecodedProgram {
  const length = size(program);
  if (length < 2) {
    throw new ProgramDecodeError(`program too short to contain even one instruction header: ${length} bytes`);
  }

  const opcode = readUint8(program, 0);
  if (opcode !== CURVE_OPCODE) {
    throw new ProgramDecodeError(`expected the curve instruction (opcode ${CURVE_OPCODE}) first, got ${opcode}`);
  }
  const curveArgsLength = readUint8(program, 1);
  const curveArgsStart = 2;
  if (length < curveArgsStart + curveArgsLength) {
    throw new ProgramDecodeError(
      `program declares ${curveArgsLength}-byte curve args but only has ${length - curveArgsStart} bytes left`,
    );
  }

  const { groups, feeBps, maxDeviationBps, end } = decodeCurveArgs(program, curveArgsStart);
  if (end !== curveArgsStart + curveArgsLength) {
    throw new ProgramDecodeError(
      `decoded curve args used ${end - curveArgsStart} bytes but the header declared ${curveArgsLength}`,
    );
  }

  let offset = curveArgsStart + curveArgsLength;
  let resolverKycToken: Address | undefined;

  // Zero or more trailing instructions may follow the curve one -- today only the KYC gate does
  // (see GatedPortfolioManagerProgramBuilder.sol), read the same way any future opcode would be:
  // skip anything this decoder doesn't recognize rather than rejecting it, so a strategy built
  // with a not-yet-decoded instruction still yields a usable curve/eligibility read.
  while (offset < length) {
    if (length < offset + 2) {
      throw new ProgramDecodeError(`trailing instruction header truncated at offset ${offset}`);
    }
    const trailingOpcode = readUint8(program, offset);
    const trailingArgsLength = readUint8(program, offset + 1);
    const argsStart = offset + 2;
    if (length < argsStart + trailingArgsLength) {
      throw new ProgramDecodeError(`trailing instruction at offset ${offset} declares args past the program's end`);
    }

    if (trailingOpcode === KYC_GATE_OPCODE) {
      if (trailingArgsLength !== 20) {
        throw new ProgramDecodeError(`KYC gate instruction args must be 20 bytes, got ${trailingArgsLength}`);
      }
      resolverKycToken = readAddress(program, argsStart);
    }

    offset = argsStart + trailingArgsLength;
  }

  return { groups, feeBps, maxDeviationBps, resolverKycToken };
}
