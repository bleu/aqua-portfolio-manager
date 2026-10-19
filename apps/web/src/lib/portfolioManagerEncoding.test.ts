import { describe, expect, it } from "vitest";
import { buildArgs, buildOrder, buildProgram, encodeOrder, type Group } from "./portfolioManagerEncoding";

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
});
