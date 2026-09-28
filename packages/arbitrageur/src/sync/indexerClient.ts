import { GraphQLClient, gql } from "graphql-request";

export interface IndexerConfig {
  graphqlUrl: string;
  adminSecret?: string;
}

export function makeIndexerClient({ graphqlUrl, adminSecret }: IndexerConfig): GraphQLClient {
  return new GraphQLClient(graphqlUrl, {
    headers: adminSecret ? { "x-hasura-admin-secret": adminSecret } : {},
  });
}

export interface IndexedStrategy {
  id: string;
  maker: string;
  app: string;
  strategyHash: string;
  tokens: string[];
  isActive: boolean;
  shippedAt: string; // BigInt serializes as a numeric string over GraphQL
  dockedAt: string | null;
}

const STRATEGIES_QUERY = gql`
  query Strategies($limit: Int!, $offset: Int!) {
    Strategy(limit: $limit, offset: $offset, order_by: { id: asc }) {
      id
      maker
      app
      strategyHash
      tokens
      isActive
      shippedAt
      dockedAt
    }
  }
`;

/// Full paginated scan, not an incremental cursor: `Strategy` rows are mutated in place (`Docked`
/// flips `isActive` on an existing row), so "everything since X" by insertion order would miss
/// updates to older rows. Cheap at the strategy counts this indexes today; a growth-driven fix
/// (e.g. indexing an `updatedAtBlock` field and filtering on it) is a real, separate follow-up if
/// the Strategy count ever makes a full scan expensive -- see this file's own README note.
export async function fetchAllStrategies(client: GraphQLClient, pageSize = 500): Promise<IndexedStrategy[]> {
  const all: IndexedStrategy[] = [];
  let offset = 0;
  for (;;) {
    const { Strategy: page } = await client.request<{ Strategy: IndexedStrategy[] }>(STRATEGIES_QUERY, {
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
  query WalletBalanceChanges($afterBlock: numeric!, $afterLogIndex: Int!, $limit: Int!) {
    WalletBalanceChange(
      where: {
        _or: [
          { blockNumber: { _gt: $afterBlock } }
          { _and: [{ blockNumber: { _eq: $afterBlock } }, { logIndex: { _gt: $afterLogIndex } }] }
        ]
      }
      order_by: [{ blockNumber: asc }, { logIndex: asc }]
      limit: $limit
    ) {
      id
      wallet
      token
      change
      blockNumber
      logIndex
    }
  }
`;

/// One page of `WalletBalanceChange` rows strictly after the given `(blockNumber, logIndex)`
/// position -- the composite cursor `syncWalletBalanceChanges` (src/sync/indexer.ts) advances
/// after each transactionally-applied batch. Never re-fetches a row already applied, so applying
/// a returned batch is safe to do without a separate idempotency check.
export async function fetchWalletBalanceChangesAfter(
  client: GraphQLClient,
  afterBlock: bigint,
  afterLogIndex: number,
  limit = 500,
): Promise<IndexedWalletBalanceChange[]> {
  const { WalletBalanceChange } = await client.request<{ WalletBalanceChange: IndexedWalletBalanceChange[] }>(
    WALLET_BALANCE_CHANGES_QUERY,
    { afterBlock: afterBlock.toString(), afterLogIndex, limit },
  );
  return WalletBalanceChange;
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
  query PriceSnapshots($afterBlock: numeric!, $afterLogIndex: Int!, $limit: Int!) {
    PriceSnapshot(
      where: {
        _or: [
          { blockNumber: { _gt: $afterBlock } }
          { _and: [{ blockNumber: { _eq: $afterBlock } }, { logIndex: { _gt: $afterLogIndex } }] }
        ]
      }
      order_by: [{ blockNumber: asc }, { logIndex: asc }]
      limit: $limit
    ) {
      id
      feedProxy
      answer
      updatedAt
      blockNumber
      blockTimestamp
      logIndex
    }
  }
`;

/// Same composite-cursor shape as `fetchWalletBalanceChangesAfter`, for `PriceSnapshot`.
export async function fetchPriceSnapshotsAfter(
  client: GraphQLClient,
  afterBlock: bigint,
  afterLogIndex: number,
  limit = 500,
): Promise<IndexedPriceSnapshot[]> {
  const { PriceSnapshot } = await client.request<{ PriceSnapshot: IndexedPriceSnapshot[] }>(PRICE_SNAPSHOTS_QUERY, {
    afterBlock: afterBlock.toString(),
    afterLogIndex,
    limit,
  });
  return PriceSnapshot;
}
