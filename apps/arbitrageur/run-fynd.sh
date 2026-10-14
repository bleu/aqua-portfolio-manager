#!/usr/bin/env bash
# Starts the local Fynd server this service's return-leg routing depends on (README's "Flash-loan
# execution" section). Fails fast with a clear message instead of Fynd's own cryptic errors for
# the two real setup problems found running this locally (BLEUDEV-400):
#   1. Fynd's default --metrics-port (9898) collides with the Envio indexer's own metrics port --
#      both bind 9898 by default, and Fynd panics on startup if the indexer is already running.
#      Picked 9899 here; override with FYND_METRICS_PORT if that's taken too.
#   2. Fynd can't start at all without a real TYCHO_API_KEY (ask PropellerHeads, or whoever issued
#      one for this project) -- its own error for this is a bare "Missing authorization token" body
#      from a failed Tycho RPC call, not an obviously-missing-env-var message.
cd "$(dirname "$0")"

if ! command -v fynd >/dev/null 2>&1; then
  echo "fynd isn't installed -- run: cargo install fynd (see README's \"Running a local Fynd server\")" >&2
  exit 1
fi

if [ -f .env.fynd ]; then
  # shellcheck disable=SC1091
  source .env.fynd
fi

if [ -z "$TYCHO_API_KEY" ]; then
  echo "TYCHO_API_KEY is not set -- ask PropellerHeads (or whoever issued one for this project)," >&2
  echo "then either export it or put TYCHO_API_KEY=... in packages/arbitrageur/.env.fynd" >&2
  echo "(see .env.fynd.example)." >&2
  exit 1
fi

exec fynd serve --chain "${FYND_CHAIN:-base}" --metrics-port "${FYND_METRICS_PORT:-9899}"
