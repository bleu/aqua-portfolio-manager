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

export interface IndexedWalletBalanceChange {
  id: string;
  wallet: string;
  token: string;
  change: string; // signed BigInt as a string
  blockNumber: string;
  logIndex: number;
}

const WALLET_BALANCE_CHANGES_QUERY = gql`
  query WalletBalanceChanges($afterBlock: BigInt!, $afterLogIndex: Int!, $limit: Int!) {
    walletBalanceChanges(
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
        wallet
        token
        change
        blockNumber
        logIndex
      }
    }
  }
`;

/// One page of `walletBalanceChange` rows strictly after the given `(blockNumber, logIndex)`
/// position -- the composite cursor `syncWalletBalanceChanges` (src/sync/indexer.ts) advances
/// after each transactionally-applied batch. Never re-fetches a row already applied, so applying
/// a returned batch is safe to do without a separate idempotency check.
///
/// Ponder's GraphQL only orders by one field (`orderBy`), unlike Hasura's multi-column
/// `order_by` list -- rows sharing a `blockNumber` come back in whatever order Postgres returns
/// them, so a single page can still mix logIndex order within one block. Harmless here: the
/// caller applies a whole page inside one transaction before advancing the cursor, and the next
/// page's `OR` condition is still anchored on the true max `(blockNumber, logIndex)` seen.
export async function fetchWalletBalanceChangesAfter(
  client: GraphQLClient,
  afterBlock: bigint,
  afterLogIndex: number,
  limit = 500,
): Promise<IndexedWalletBalanceChange[]> {
  const {
    walletBalanceChanges: { items },
  } = await client.request<{ walletBalanceChanges: { items: IndexedWalletBalanceChange[] } }>(
    WALLET_BALANCE_CHANGES_QUERY,
    { afterBlock: afterBlock.toString(), afterLogIndex, limit },
  );
  return items;
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

/// Same composite-cursor shape and same single-column-orderBy caveat as
/// `fetchWalletBalanceChangesAfter`, for `priceSnapshot`.
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
