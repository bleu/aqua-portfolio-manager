import { serve } from "@hono/node-server";
import { loadConfig } from "./config.js";
import { makeClients } from "./chain.js";
import { makeDb } from "./db/client.js";
import { makeRedisConnection } from "./queue/redis.js";
import { makeQueues } from "./queue/queues.js";
import { makeIndexerClient } from "./sync/indexerClient.js";
import { FyndClient } from "./fynd.js";
import { startWorkers, stopWorkers, type Workers } from "./workers.js";
import { makeApiServer } from "./api/server.js";

/// ADR-0014's production arbitrageur: an Envio-backed indexer sync, six BullMQ queues wiring
/// Strategy Catalog through Execution and Tracking (see src/workers.ts), and a read-only
/// Operations API -- replacing the static-config, single-tick experiment this package used to
/// run (see BLEUDEV-393's own PR history for that migration).
async function main() {
  const config = loadConfig();
  const db = makeDb(config.databaseUrl);
  const redis = makeRedisConnection(config.redisUrl);
  const queues = makeQueues(redis);
  const clients = makeClients(config);
  const indexerClient = makeIndexerClient({ graphqlUrl: config.indexerGraphqlUrl, adminSecret: config.indexerAdminSecret });
  const fyndClient = new FyndClient({ baseUrl: config.fyndUrl, chain: config.fyndChain, timeoutMs: config.fyndTimeoutMs });

  console.log(
    `arbitrageur starting: executor=${config.arbitrageurAddress} allowedTokens=${config.allowedTokens.length} ` +
      `dryRun=${config.dryRun} fynd=${config.fyndUrl} indexer=${config.indexerGraphqlUrl}`,
  );

  let workers: Workers | undefined;
  try {
    workers = await startWorkers({
      db,
      clients,
      publicClient: clients.publicClient,
      fyndClient,
      indexerClient,
      config,
      queues,
    });
  } catch (err) {
    console.error(`failed to start workers: ${err instanceof Error ? err.message : err}`);
    process.exitCode = 1;
    return;
  }

  const api = makeApiServer({ db, config });
  const server = serve({ fetch: api.fetch, port: config.operationsApiPort }, (info) => {
    console.log(`Operations API listening on :${info.port}`);
  });

  const stop = async () => {
    console.log("shutting down...");
    server.close();
    if (workers) await stopWorkers(workers);
    await redis.quit();
    process.exit(0);
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
