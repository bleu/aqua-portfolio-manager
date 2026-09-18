import type { Address, PublicClient } from "viem";
import { aggregatorV3Abi } from "./abi.js";

const WAD = 10n ** 18n;

export class StaleOracleError extends Error {
  constructor(feed: Address, updatedAt: bigint, maxStaleness: number) {
    super(`Oracle feed ${feed} is stale: updatedAt=${updatedAt}, maxStaleness=${maxStaleness}s`);
  }
}

/// Mirrors `OracleAdapter.priceWad` in packages/contracts/src/utils/OracleAdapter.sol exactly:
/// same feed, same staleness rule, same WAD normalization -- this is deliberately the identical
/// price PM's own swap opcode reads, not an independent source, since the whole point is
/// detecting when PM's *curve* price has drifted from the *oracle* price it's supposed to track.
export async function readOraclePriceWad(
  client: PublicClient,
  feed: Address,
  maxStalenessSeconds: number,
): Promise<bigint> {
  const [decimals, roundData] = await Promise.all([
    client.readContract({ address: feed, abi: aggregatorV3Abi, functionName: "decimals" }),
    client.readContract({ address: feed, abi: aggregatorV3Abi, functionName: "latestRoundData" }),
  ]);
  const [, answer, , updatedAt] = roundData;

  if (answer <= 0n) {
    throw new Error(`Oracle feed ${feed} returned a non-positive price: ${answer}`);
  }

  const block = await client.getBlock();
  const staleness = block.timestamp - updatedAt;
  if (updatedAt > block.timestamp || staleness > BigInt(maxStalenessSeconds)) {
    throw new StaleOracleError(feed, updatedAt, maxStalenessSeconds);
  }

  const rawPrice = answer as bigint;
  if (decimals < 18) {
    return rawPrice * 10n ** BigInt(18 - decimals);
  }
  if (decimals > 18) {
    return rawPrice / 10n ** BigInt(decimals - 18);
  }
  return rawPrice;
}

export { WAD };
