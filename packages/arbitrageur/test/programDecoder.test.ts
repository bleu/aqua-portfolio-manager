import { describe, expect, it } from "vitest";
import { decodeProgram, ProgramDecodeError } from "../src/domains/programDecoder.js";

// Real bytes from the actual Solidity builders (PortfolioManagerProgramBuilder.build /
// GatedPortfolioManagerProgramBuilder.build), not hand-encoded -- generated once via a throwaway
// forge test calling both builders with these exact addresses/weights/fee/deviation/gate token,
// then discarded. This is the strongest check available for a decoder that must stay byte-exact
// with PortfolioManagerArgsCodec.sol without a live Solidity toolchain in every test run.
const UNGATED_PROGRAM =
  "0x00a9020000000000000000058d15e176280000017e5f4552091a69125d5dfcb7b8c2659029395bdf2b5ad5c4795c026514f8317c7a215e218dccd6cf0e1000000000000000000853a0d2313c0000026813eb9362372eef6200f3b1dbc3f819671cba691eff47bc3a10a45d4b230b5d10e37751fe6aa7181c20e1ab8145f7e55dc933d51a18c793f901a3a0b276e57bfe9f44b819898f47bf37e5af72a0783e114103840000001e000001f4" as const;

const GATED_PROGRAM =
  "0x00a9020000000000000000058d15e176280000017e5f4552091a69125d5dfcb7b8c2659029395bdf2b5ad5c4795c026514f8317c7a215e218dccd6cf0e1000000000000000000853a0d2313c0000026813eb9362372eef6200f3b1dbc3f819671cba691eff47bc3a10a45d4b230b5d10e37751fe6aa7181c20e1ab8145f7e55dc933d51a18c793f901a3a0b276e57bfe9f44b819898f47bf37e5af72a0783e114103840000001e000001f40114d41c057fd1c78805aac12b0a94a405c0461a6fbb" as const;

const TOKEN_A = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf";
const FEED_A = "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf";
const TOKEN_B1 = "0x6813eb9362372eef6200f3b1dbc3f819671cba69";
const FEED_B1 = "0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718";
const TOKEN_B2 = "0xe1ab8145f7e55dc933d51a18c793f901a3a0b276";
const FEED_B2 = "0xe57bfe9f44b819898f47bf37e5af72a0783e1141";
const KYC_TOKEN = "0xd41c057fd1c78805aac12b0a94a405c0461a6fbb";

describe("decodeProgram", () => {
  it("decodes an ungated program to match what PortfolioManagerProgramBuilder.build actually encoded", () => {
    const decoded = decodeProgram(UNGATED_PROGRAM);

    expect(decoded.resolverKycToken).toBeUndefined();
    expect(decoded.feeBps).toBe(30);
    expect(decoded.maxDeviationBps).toBe(500);
    expect(decoded.groups).toHaveLength(2);

    expect(decoded.groups[0]!.weightWad).toBe(400000000000000000n);
    expect(decoded.groups[0]!.members).toEqual([{ token: TOKEN_A, feed: FEED_A, maxStaleness: 3600 }]);

    expect(decoded.groups[1]!.weightWad).toBe(600000000000000000n);
    expect(decoded.groups[1]!.members).toEqual([
      { token: TOKEN_B1, feed: FEED_B1, maxStaleness: 7200 },
      { token: TOKEN_B2, feed: FEED_B2, maxStaleness: 900 },
    ]);
  });

  it("decodes a gated program's resolver KYC token from what GatedPortfolioManagerProgramBuilder.build actually encoded", () => {
    const decoded = decodeProgram(GATED_PROGRAM);

    expect(decoded.feeBps).toBe(30);
    expect(decoded.groups).toHaveLength(2);
    expect(decoded.resolverKycToken).toBe(KYC_TOKEN);
  });

  it("throws ProgramDecodeError when the program doesn't start with the curve opcode", () => {
    expect(() => decodeProgram("0x0100")).toThrow(ProgramDecodeError);
  });

  it("throws ProgramDecodeError when the curve args are shorter than declared", () => {
    expect(() => decodeProgram("0x00ff0000")).toThrow(ProgramDecodeError);
  });

  it("throws ProgramDecodeError when a trailing instruction's args run past the program's end", () => {
    // A minimal but structurally complete curve instruction (0 groups, feeBps=0,
    // maxDeviationBps=0 -- 9 bytes of args, matching decodeTrusted's own lack of MIN_GROUPS
    // enforcement), followed by a KYC gate header claiming 20 bytes of args it doesn't have.
    expect(() => decodeProgram("0x00090000000000000000000114")).toThrow(ProgramDecodeError);
  });
});
