#!/usr/bin/env bash
set -exo pipefail

# Get the root directory of the current git repository and the current commit hash
REPO_ROOT_DIR=$(git rev-parse --show-toplevel)
APP_REVISION=$(git rev-parse --short HEAD)

# Parse arguments: target (host:path or '-') and optional env file path
DEPLOY_TARGET="${1:-}"
ENV_FILE_PATH="${2:-}"

if [[ -z "$DEPLOY_TARGET" ]]; then
    echo "Usage: $0 <deploy_target> [env_file_path]"
    exit 1
fi

if [[ "$DEPLOY_TARGET" == "-" ]]; then
    TARGET_DEPLOY_DIR="$REPO_ROOT_DIR"
    REMOTE_CMD_PREFIX=""
elif [[ "$DEPLOY_TARGET" =~ ^[^:]+:.+ ]]; then
    SSH_HOST=$(echo "$DEPLOY_TARGET" | cut -d':' -f1)
    REMOTE_PATH=$(echo "$DEPLOY_TARGET" | cut -d':' -f2-)
    # --mkpath needs a newer (GNU) rsync than macOS ships by default -- creating the remote
    # directory explicitly first works with either.
    ssh "$SSH_HOST" "mkdir -p '$REMOTE_PATH'"

    # Sync the whole monorepo, not just apps/indexer -- the Dockerfile builds from the repo root
    # (this package depends on @aqua-portfolio-manager/addresses via a pnpm workspace link).
    # Every other package's own .env*/.vercel is excluded on purpose: this only needs to ship this
    # one deployment's own .env (the one --include lets through) to the remote, never another
    # app's local secrets (apps/web/.env.local's Vercel OIDC token, a Safe API key, etc.) that
    # happen to live in the same working tree.
    rsync -avz --delete \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='.tmp' \
        --exclude='.next' \
        --exclude='.vercel' \
        --exclude='simulation' \
        --exclude='packages/contracts/cache' \
        --exclude='packages/contracts/out' \
        --exclude='packages/contracts/broadcast' \
        --include='apps/indexer/deployment/.env' \
        --exclude='.env*' \
        "$REPO_ROOT_DIR/" "$SSH_HOST:$REMOTE_PATH/"
    TARGET_DEPLOY_DIR="$REMOTE_PATH"
    REMOTE_CMD_PREFIX="ssh $SSH_HOST"
else
    echo "Error: <deploy_target> must be '-' or in the format SSH_HOST:PATH"
    exit 1
fi

# This repo's deployment dir lives under apps/indexer, not at the repo root (picnic-indexer's own
# single-package layout has it at the root -- this script otherwise matches that one verbatim).
APP_DEPLOY_DIR="$TARGET_DEPLOY_DIR/apps/indexer/deployment"
# manage.sh cd's into its own directory before sourcing this, so the default must be an absolute
# path -- a bare ".env" would otherwise be looked up relative to the SSH login shell's own cwd,
# not this deployment directory.
ENV_FILE_PATH="${ENV_FILE_PATH:-$APP_DEPLOY_DIR/.env}"

# Run deployment commands (locally or remotely)
$REMOTE_CMD_PREFIX bash -c "
    set -euo pipefail
    bash $APP_DEPLOY_DIR/manage.sh ${MANAGE_CMD_OVERRIDE:-up} \
        --env-file '$ENV_FILE_PATH' \
        --revision '$APP_REVISION'
"
