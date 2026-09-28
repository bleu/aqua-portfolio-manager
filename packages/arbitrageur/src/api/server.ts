import { Hono } from "hono";
import { desc } from "drizzle-orm";
import type { Db } from "../db/client.js";
import { strategies, strategyWalletBalances, candidates, executionAttempts } from "../db/schema.js";
import type { Config } from "../config.js";

export interface ApiDeps {
  db: Db;
  config: Config;
}

/// Operations API (ADR-0014): "Return authenticated, read-only operational data." No write
/// endpoints, no secrets in any response -- /v1/config below is the one endpoint that could leak
/// something if built carelessly, so it lists safe fields explicitly rather than spreading
/// `config` and hoping nothing sensitive is in it.
export function makeApiServer(deps: ApiDeps): Hono {
  const app = new Hono();

  app.use("*", async (c, next) => {
    if (c.req.path === "/health") return next(); // health must stay reachable without auth for infra checks
    const auth = c.req.header("authorization");
    if (auth !== `Bearer ${deps.config.operationsApiToken}`) {
      return c.json({ error: "unauthorized" }, 401);
    }
    return next();
  });

  app.get("/health", async (c) => {
    try {
      await deps.db.query.strategies.findFirst();
      return c.json({ status: "ok", dryRun: deps.config.dryRun });
    } catch (err) {
      return c.json({ status: "unhealthy", reason: err instanceof Error ? err.message : "unknown" }, 503);
    }
  });

  app.get("/v1/strategies", async (c) => {
    const rows = await deps.db.query.strategies.findMany({ orderBy: desc(strategies.shippedAt) });
    return c.json({ strategies: rows });
  });

  app.get("/v1/strategy-wallets", async (c) => {
    const rows = await deps.db.query.strategyWalletBalances.findMany({
      orderBy: desc(strategyWalletBalances.updatedAt),
    });
    return c.json({ balances: rows });
  });

  app.get("/v1/candidates", async (c) => {
    const rows = await deps.db.query.candidates.findMany({ orderBy: desc(candidates.createdAt), limit: 200 });
    return c.json({ candidates: rows });
  });

  app.get("/v1/execution-attempts", async (c) => {
    const rows = await deps.db.query.executionAttempts.findMany({
      orderBy: desc(executionAttempts.createdAt),
      limit: 200,
    });
    return c.json({ executionAttempts: rows });
  });

  app.get("/v1/config", (c) => {
    const { config } = deps;
    return c.json({
      arbitrageurAddress: config.arbitrageurAddress,
      executorVersion: config.executorVersion,
      allowedTokens: config.allowedTokens,
      fyndChain: config.fyndChain,
      minTradeAmount: config.minTradeAmount.toString(),
      maxTradeAmount: config.maxTradeAmount.toString(),
      minProfitUsdWad: config.minProfitUsdWad.toString(),
      maxPriceStalenessSeconds: config.maxPriceStalenessSeconds.toString(),
      slippageBufferBps: config.slippageBufferBps.toString(),
      deadlineBufferSeconds: config.deadlineBufferSeconds,
      confirmationDepth: config.confirmationDepth,
      maxRetries: config.maxRetries,
      syncIntervalMs: config.syncIntervalMs,
      dryRun: config.dryRun,
      // Deliberately omitted: privateKey, databaseUrl, redisUrl, indexerAdminSecret,
      // slackWebhookUrl, operationsApiToken -- "The API does not return secrets."
    });
  });

  return app;
}
