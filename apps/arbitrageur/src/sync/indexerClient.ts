import { GraphQLClient, gql } from "graphql-request";

export interface IndexerConfig {
  graphqlUrl: string;
}

export function makeIndexerClient({ graphqlUrl }: IndexerConfig): GraphQLClient {
  return new GraphQLClient(graphqlUrl);
}

export interface IndexedStrategy {
  id: string;
  maker: string;
  app: string;
  strategyHash: string;
  encodedOrder: string;
  tokens: string[];
  isActive: boolean;
  shippedAt: string; // BigInt serializes as a numeric string over GraphQL
  dockedAt: string | null;
}

const STRATEGIES_QUERY = gql`
  query Strategies($limit: Int!, $offset: Int!) {
    strategys(limit: $limit, offset: $offset, orderBy: "id", orderDirection: "asc") {
      items {
        id
        maker
        app
        strategyHash
        encodedOrder
        tokens
        isActive
        shippedAt
        dockedAt
      }
    }
  }
`;

/// Full paginated scan, not an incremental cursor: `strategy` rows are mutated in place (`Docked`
/// flips `isActive` on an existing row), so "everything since X" by insertion order would miss
/// updates to older rows. Cheap at the strategy counts this indexes today; a growth-driven fix
/// (e.g. indexing an `updatedAtBlock` field and filtering on it) is a real, separate follow-up if
/// the Strategy count ever makes a full scan expensive -- see this file's own README note.
export async function fetchAllStrategies(client: GraphQLClient, pageSize = 500): Promise<IndexedStrategy[]> {
  const all: IndexedStrategy[] = [];
  let offset = 0;
  for (;;) {
    const {
      strategys: { items: page },
    } = await client.request<{ strategys: { items: IndexedStrategy[] } }>(STRATEGIES_QUERY, {
      limit: pageSize,
      offset,
    });
    all.push(...page);
    if (page.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

export interface IndexedPriceSnapshot {
  id: string;
  feedProxy: string;
  answer: string; // signed BigInt as a string
  updatedAt: string;
  blockNumber: string;
  blockTimestamp: string;
  logIndex: number;
}

const PRICE_SNAPSHOTS_QUERY = gql`
  query PriceSnapshots($afterBlock: BigInt!, $afterLogIndex: Int!, $limit: Int!) {
    priceSnapshots(
      where: {
        OR: [
          { blockNumber_gt: $afterBlock }
          { AND: [{ blockNumber: $afterBlock }, { logIndex_gt: $afterLogIndex }] }
        ]
      }
      orderBy: "blockNumber"
      orderDirection: "asc"
      limit: $limit
    ) {
      items {
        id
        feedProxy
        answer
        updatedAt
        blockNumber
        blockTimestamp
        logIndex
      }
    }
  }
`;

/// Composite cursor on `(blockNumber, logIndex)`, strictly-after. Ponder's GraphQL only orders by
/// one field, so rows sharing a `blockNumber` can come back in any order within one page --
/// harmless here since the caller applies a whole page in one transaction before advancing past
/// the true max `(blockNumber, logIndex)` seen.
export async function fetchPriceSnapshotsAfter(
  client: GraphQLClient,
  afterBlock: bigint,
  afterLogIndex: number,
  limit = 500,
): Promise<IndexedPriceSnapshot[]> {
  const {
    priceSnapshots: { items },
  } = await client.request<{ priceSnapshots: { items: IndexedPriceSnapshot[] } }>(PRICE_SNAPSHOTS_QUERY, {
    afterBlock: afterBlock.toString(),
    afterLogIndex,
    limit,
  });
  return items;
}
