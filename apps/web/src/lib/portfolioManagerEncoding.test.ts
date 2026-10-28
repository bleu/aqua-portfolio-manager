import { describe, expect, it } from "vitest";
import { appendNonceToProgram, buildArgs, buildOrder, buildProgram, decodeOrder, encodeOrder, type Group } from "./portfolioManagerEncoding";

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
});
