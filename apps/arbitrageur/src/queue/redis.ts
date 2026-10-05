import IORedis from "ioredis";

/// BullMQ's own documented requirement: a blocking client (which BullMQ uses internally for
/// waiting on jobs) must disable ioredis's request-level retry, or a blocking call can hang
/// forever retrying instead of surfacing the error.
export function makeRedisConnection(redisUrl: string): IORedis {
  return new IORedis(redisUrl, { maxRetriesPerRequest: null });
}
