#!/usr/bin/env bash
# Restarts `pnpm dev` whenever it exits for any reason, including an OS-level low-memory kill --
# BullMQ's job state lives in Redis, not the Node process, so a restart just reconnects workers to
# the same queues; it never resubmits a transaction that already went out (see workers.ts's own
# idempotency notes). Backs off 5s between restarts so a genuine crash-loop doesn't spin the CPU.
# Ctrl+C stops it for good.
cd "$(dirname "$0")"
while true; do
  pnpm dev
  code=$?
  echo "arbitrageur exited (code $code) -- restarting in 5s. Ctrl+C to stop for good."
  sleep 5
done
