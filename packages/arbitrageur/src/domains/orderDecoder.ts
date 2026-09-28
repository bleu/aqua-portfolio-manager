import { decodeAbiParameters, slice, type Address, type Hex } from "viem";

export interface DecodedOrder {
  maker: Address;
  traits: bigint;
  data: Hex;
}

const ORDER_ABI_PARAMS = [
  {
    type: "tuple",
    components: [
      { name: "maker", type: "address" },
      { name: "traits", type: "uint256" },
      { name: "data", type: "bytes" },
    ],
  },
] as const;

/// The bytes Aqua's `Shipped` event carries (mirrored into `strategies.program` by the
/// sync-indexer job) are `abi.encode(order)`, an `ISwapVM.Order` -- not the bare program bytes
/// directly (`Aqua.ship`'s `strategy` argument is exactly what gets hashed and emitted, and
/// `strategyHash = keccak256(strategy)` matches `ISwapVM.hash`'s "keccak256(abi.encode(order))
/// for Aqua orders" doc comment). This is the ABI decode step that has to happen before
/// `extractProgram`/`decodeProgram` can run on real indexed data.
export function decodeOrder(encodedOrder: Hex): DecodedOrder {
  const [order] = decodeAbiParameters(ORDER_ABI_PARAMS, encodedOrder);
  return { maker: order.maker, traits: order.traits, data: order.data };
}

/// Matches MakerTraitsLib.sol's own bit layout exactly: four uint16 slice-end offsets packed
/// into `traits` starting at bit 160, one per 16-bit field, indexed 0-3 for the four maker-hook
/// data slices (pre/post transfer-in, pre/post transfer-out).
const ORDER_DATA_SLICES_INDEXES_BIT_OFFSET = 160n;
const ORDER_DATA_SLICES_INDEX_BIT_MASK = 0xffffn;

function getOffset(traits: bigint, sliceNumber: bigint): number {
  const bitShift = sliceNumber * 16n;
  return Number((traits >> ORDER_DATA_SLICES_INDEXES_BIT_OFFSET >> bitShift) & ORDER_DATA_SLICES_INDEX_BIT_MASK);
}

/// Mirrors `MakerTraitsLib.program(traits, data)` exactly (verified against real Solidity output
/// -- see programDecoder.test.ts's OrderFixture-derived cases): the program slice is always the
/// last one in `data`, starting right after the fourth hook slice's own end offset and running to
/// `data`'s end. A strategy with no maker hooks has that offset at 0, so `data` is the program
/// bytes directly in that case -- but this reads the real offset the order declares rather than
/// assuming it.
export function extractProgram(traits: bigint, data: Hex): Hex {
  const programStart = getOffset(traits, 3n);
  return slice(data, programStart);
}
