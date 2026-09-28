import { describe, expect, it } from "vitest";
import { decodeOrder, extractProgram } from "../src/domains/orderDecoder.js";

// Real bytes from an actual MakerTraitsLib.build(...) + abi.encode(order) call (a no-hooks PM
// order: shouldUnwrapWeth=false, useAquaInsteadOfSignature=true, receiver=address(0)), generated
// via a throwaway forge test and discarded -- the same real-fixture approach programDecoder's own
// test uses, since this decoder has to stay byte-exact with MakerTraitsLib.sol without a live
// Solidity toolchain in every test run. The forge test itself also asserted, on the Solidity
// side, that MakerTraitsLib.program(order.traits, order.data) recovers this exact PROGRAM value.
// viem's decodeAbiParameters returns an EIP-55 checksummed address, not the lowercase form the
// forge test printed -- same value, different case.
const MAKER = "0x24D881139Ee639C2A774B4B1851CB7a9d0fce122";
const TRAITS = 28948022309329048855892746252171976963317496166410141009864396001978282409984n; // 1 << 254
const PROGRAM =
  "0x007f02000000000000000006f05b59d3b20000017e5f4552091a69125d5dfcb7b8c2659029395bdf2b5ad5c4795c026514f8317c7a215e218dccd6cf0e10000000000000000006f05b59d3b20000016813eb9362372eef6200f3b1dbc3f819671cba691eff47bc3a10a45d4b230b5d10e37751fe6aa7180e100000001e00000000" as const;
const ENCODED_ORDER =
  "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000024d881139ee639c2a774b4b1851cb7a9d0fce122400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000081007f02000000000000000006f05b59d3b20000017e5f4552091a69125d5dfcb7b8c2659029395bdf2b5ad5c4795c026514f8317c7a215e218dccd6cf0e10000000000000000006f05b59d3b20000016813eb9362372eef6200f3b1dbc3f819671cba691eff47bc3a10a45d4b230b5d10e37751fe6aa7180e100000001e0000000000000000000000000000000000000000000000000000000000000000000000" as const;

describe("decodeOrder", () => {
  it("decodes maker, traits, and data from a real abi.encode(order) blob", () => {
    const order = decodeOrder(ENCODED_ORDER);
    expect(order.maker).toBe(MAKER);
    expect(order.traits).toBe(TRAITS);
    expect(order.data).toBe(PROGRAM); // no-hooks order: data IS the program bytes directly
  });
});

describe("extractProgram", () => {
  it("recovers the exact program bytes MakerTraitsLib.program() recovers on the Solidity side", () => {
    const order = decodeOrder(ENCODED_ORDER);
    expect(extractProgram(order.traits, order.data)).toBe(PROGRAM);
  });

  it("returns the full data when traits declares zero-length hook slices (the no-hooks case)", () => {
    // Every slice-end offset packed into TRAITS is 0 here (traits == 1<<254 exactly, nothing
    // else set), so the Program slice starts at byte 0 -- `data` unchanged.
    expect(extractProgram(TRAITS, PROGRAM)).toBe(PROGRAM);
  });

  it("skips a leading hook slice when traits declares a nonzero offset", () => {
    const dataWithPrefix = `0xdeadbeef${PROGRAM.slice(2)}` as const;
    // index3 = 4 (bytes) packed at bit 160+48; every other slice offset left at 0.
    const traitsWithFourByteHook = 4n << 208n; // (3 << 4) = 48; 160+48 = 208
    expect(extractProgram(traitsWithFourByteHook, dataWithPrefix)).toBe(PROGRAM);
  });
});
