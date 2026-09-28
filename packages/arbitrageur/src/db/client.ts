import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as schema from "./schema.js";

/// This service's own Postgres, distinct from `packages/indexer`'s Envio-managed database --
/// `sync-indexer` is the only bridge between the two (see `src/sync/indexer.ts`), reading
/// Envio's exposed GraphQL API and writing here.
export function makeDb(databaseUrl: string) {
  const pool = new Pool({ connectionString: databaseUrl });
  return drizzle(pool, { schema });
}

export type Db = ReturnType<typeof makeDb>;
