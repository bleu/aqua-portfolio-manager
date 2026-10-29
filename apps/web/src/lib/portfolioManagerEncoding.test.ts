import { describe, expect, it } from "vitest";
import {
  appendNonceToProgram,
  buildArgs,
  buildOrder,
  buildProgram,
  decodeGroups,
  decodeOrder,
  decodeOrderGroups,
  encodeOrder,
  isReshipOf,
  programByteLength,
  type Group,
} from "./portfolioManagerEncoding";

/** Golden vectors captured from the real Solidity implementation via
 *  packages/contracts/test/PortfolioManagerEncodingGoldenVectors.t.sol (`forge test
 *  --match-contract PortfolioManagerEncodingGoldenVectorsTest -vv`), for
 *  PortfolioManagerArgsCodec.build /
 *  PortfolioManagerProgramBuilder.build / MakerTraitsLib.build. Re-run that script and update
 *  these constants if the Solidity encoding ever changes. */
const GROUPS: Group[] = [
  {
    weightWad: 600_000_000_000_000_000n, // 0.6e18
    members: [
      { tokenIndex: 5, feedIndex: 7 },
      { tokenIndex: 9, feedIndex: 0 },
    ],
  },
  {
    weightWad: 400_000_000_000_000_000n, // 0.4e18
    members: [{ tokenIndex: 12, feedIndex: 3 }],
  },
];
const FEE_BPS_PM = 10_000_000n;
const MAX_DEVIATION_BPS_PM = 50_000_000n;
const MAKER = "0x1111111111111111111111111111111111111111" as const;

const EXPECTED_ARGS = "0x0223c3460002000500070009000017d7840001000c0003000098968002faf080";
const EXPECTED_PROGRAM = "0x00200223c3460002000500070009000017d7840001000c0003000098968002faf080";
const EXPECTED_ORDER_ENCODING =
  "0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000111111111111111111111111111111111111111140000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002200200223c3460002000500070009000017d7840001000c0003000098968002faf080000000000000000000000000000000000000000000000000000000000000";

describe("portfolioManagerEncoding", () => {
  it("buildArgs matches PortfolioManagerArgsCodec.build's real output", () => {
    expect(buildArgs(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM)).toBe(EXPECTED_ARGS);
  });

  it("buildProgram matches PortfolioManagerProgramBuilder.build's real output", () => {
    expect(buildProgram(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM)).toBe(EXPECTED_PROGRAM);
  });

  it("encodeOrder matches abi.encode(MakerTraitsLib.build(...)) for the no-hooks case", () => {
    const program = buildProgram(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const order = buildOrder(MAKER, program);
    expect(order.traits).toBe(1n << 254n);
    expect(order.data).toBe(program);
    expect(encodeOrder(order)).toBe(EXPECTED_ORDER_ENCODING);
  });

  it("decodeOrder is the exact reverse of encodeOrder", () => {
    const program = buildProgram(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const order = buildOrder(MAKER, program);
    expect(decodeOrder(encodeOrder(order))).toEqual(order);
  });

  it("appendNonceToProgram changes only the program's trailing bytes and its length header", () => {
    const program = buildProgram(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const nonced = appendNonceToProgram(program, "0xdeadbeef");

    expect(nonced).not.toBe(program);
    expect(nonced.endsWith("deadbeef")).toBe(true);
    // opcode (byte 0) unchanged; the real args bytes (everything after the 2-byte header) are an
    // untouched prefix of the new args; only argsLength (byte 1) grew, by the nonce's 4 bytes.
    expect(nonced.slice(0, 4)).toBe(program.slice(0, 4));
    expect(nonced.slice(6).startsWith(program.slice(6))).toBe(true);
    const originalArgsLength = Number.parseInt(program.slice(4, 6), 16);
    expect(Number.parseInt(nonced.slice(4, 6), 16)).toBe(originalArgsLength + 4);
  });

  it("decodeGroups is the exact reverse of buildArgs' group-encoding section", () => {
    const args = buildArgs(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const decoded = decodeGroups(args);

    expect(decoded).toHaveLength(2);
    expect(decoded[0]!.tokenIndices).toEqual([5, 9]);
    expect(decoded[1]!.tokenIndices).toEqual([12]);
    // 0.6e18/0.4e18 WAD weights, PM_BPS-scaled (1e9 = 100%) -- matches GROUPS' own weightWad split.
    expect(decoded[0]!.weightBps / 1e9).toBeCloseTo(0.6, 5);
    expect(decoded[1]!.weightBps / 1e9).toBeCloseTo(0.4, 5);
    expect(decoded[0]!.weightBps + decoded[1]!.weightBps).toBe(1_000_000_000);
  });

  it("decodeOrderGroups decodes straight from a full encodedOrder blob, matching decodeGroups(buildArgs(...))", () => {
    const program = buildProgram(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const order = buildOrder(MAKER, program);
    expect(decodeOrderGroups(encodeOrder(order))).toEqual(decodeGroups(buildArgs(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM)));
  });

  it("appendNonceToProgram's nonce bytes decode as if they weren't there -- the real reship guarantee", () => {
    // The ported buildArgs/buildProgram can't re-derive groups/fee/deviation back out (there's no
    // TS decoder), so this instead confirms the *mechanism* reship relies on using the real
    // Solidity behavior already verified separately: PortfolioManagerArgsCodec.parse() and
    // decodeTrusted() only read fixed offsets through maxDeviationBps and never check they
    // consume the whole args blob (confirmed by reading both functions directly). A program
    // whose own argsLength header correctly covers the nonce is exactly the well-formed input
    // those functions see -- this test pins that the header bookkeeping is right.
    const program = buildProgram(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const nonce = "0x0102030405060708";
    const nonced = appendNonceToProgram(program, nonce);

    const declaredArgsLength = Number.parseInt(nonced.slice(4, 6), 16);
    const actualArgsBytes = (nonced.length - 6) / 2; // total hex chars, minus "0x" and the 2-byte header, /2
    expect(declaredArgsLength).toBe(actualArgsBytes);
  });

  describe("isReshipOf", () => {
    const program = buildProgram(GROUPS, FEE_BPS_PM, MAX_DEVIATION_BPS_PM);
    const original = encodeOrder(buildOrder(MAKER, program));

    it("recognizes a real reship (parent's program plus a trailing nonce) as a child of its parent", () => {
      const reshipped = encodeOrder(buildOrder(MAKER, appendNonceToProgram(program, "0xdeadbeef")));
      expect(isReshipOf(reshipped, original)).toBe(true);
      expect(isReshipOf(original, reshipped)).toBe(false); // direction matters: parent is never a child of its own reship
    });

    it("recognizes a chain of two reships, each one generation apart", () => {
      const first = encodeOrder(buildOrder(MAKER, appendNonceToProgram(program, "0x01020304")));
      const second = encodeOrder(buildOrder(MAKER, appendNonceToProgram(appendNonceToProgram(program, "0x01020304"), "0x05060708")));
      expect(isReshipOf(second, first)).toBe(true);
      expect(isReshipOf(second, original)).toBe(true); // also a descendant of the original, two generations back
    });

    it("rejects two genuinely unrelated strategies, even same maker, even same byte length", () => {
      const unrelatedProgram = buildProgram(
        [GROUPS[1]!, GROUPS[0]!], // same groups, swapped order -- different real bytes, same length
        FEE_BPS_PM,
        MAX_DEVIATION_BPS_PM,
      );
      const unrelated = encodeOrder(buildOrder(MAKER, unrelatedProgram));
      expect(isReshipOf(unrelated, original)).toBe(false);
    });

    it("rejects a different maker's otherwise-identical strategy", () => {
      const reshipped = encodeOrder(buildOrder("0x2222222222222222222222222222222222222222", appendNonceToProgram(program, "0xdeadbeef")));
      expect(isReshipOf(reshipped, original)).toBe(false);
    });
  });

  describe("programByteLength", () => {
    // Real encodedOrder pair pulled from the production indexer (one Safe's actual reship):
    // both strings are the exact same length (450 hex chars) because the reship's nonce still
    // fits inside the same 32-byte abi-encoding padding slot as its parent -- confirmed by
    // decoding: the child's args are the parent's own args plus an 8-byte nonce. Pins the bug
    // PortfolioManagerHistoryPage's own findReshipParent hit: ordering a reship chain by
    // encodedOrder.length alone can't tell these two generations apart.
    const REAL_PARENT =
      "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000ba288819af70a3ab5496238032c5a8c743d48024000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000260024021ee1cd2802001e001e002000201cb8fcd80200260026000500050001312d0002faf0800000000000000000000000000000000000000000000000000000";
    const REAL_CHILD =
      "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000ba288819af70a3ab5496238032c5a8c743d480240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002e002c021ee1cd2802001e001e002000201cb8fcd80200260026000500050001312d0002faf0809a3fa5ad12a4a329000000000000000000000000000000000000";

    it("tells the real parent and child apart even though their encodedOrder strings are the same length", () => {
      expect(REAL_PARENT.length).toBe(REAL_CHILD.length);
      expect(programByteLength(REAL_CHILD)).toBeGreaterThan(programByteLength(REAL_PARENT));
      expect(isReshipOf(REAL_CHILD, REAL_PARENT)).toBe(true);
    });
  });
});
