#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  up      Deploy the stack
  down    Tear down the stack

Options:
  -e, --env-file <path>   Path to .env file (required)
  -r, --revision <rev>    Application revision (required for 'up')
  -h, --help              Show this help message
EOF
    exit 1
}

# --- Parse arguments ---
COMMAND="${1:-}"
shift || true

ENV_FILE_PATH=""
APP_REVISION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--env-file)
            ENV_FILE_PATH="$2"
            shift 2
            ;;
        -r|--revision)
            APP_REVISION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$COMMAND" ]]; then
    echo "Error: command is required (up|down)"
    usage
fi

if [[ -z "$ENV_FILE_PATH" ]]; then
    echo "Error: --env-file is required"
    usage
fi

if [[ -z "$APP_REVISION" ]]; then
    echo "Error: --revision is required"
    usage
fi

# --- Load environment ---
APP_DEPLOY_DIR="$(dirname "$(realpath "$0")")"
cd "$APP_DEPLOY_DIR"

set -a
source "$ENV_FILE_PATH"
set +a

if [[ -z "${PROJECT_PREFIX:-}" ]]; then
    echo "Error: PROJECT_PREFIX must be defined in the env file"
    exit 1
fi

export PROJECT_PREFIX
export APP_REVISION

# --- Commands ---
cmd_up() {
    if [[ -z "$APP_REVISION" ]]; then
        echo "Error: --revision is required for 'up'"
        exit 1
    fi

    echo ">>> Building API image..."
    EXTERNAL_RESOURCES=true docker compose \
        -p "${PROJECT_PREFIX}-stack" -f docker-stack.yml \
        build --build-arg BUILDKIT_INLINE_CACHE=1

    echo ">>> Starting dependencies..."
    docker compose \
        -p "${PROJECT_PREFIX}" -f docker-compose.yml \
        up -d --remove-orphans

    sleep 3s

    echo ">>> Deploying stack..."
    EXTERNAL_RESOURCES=true docker stack deploy \
        --compose-file docker-stack.yml \
        --prune --detach --with-registry-auth --resolve-image never \
        "${PROJECT_PREFIX}"
}

cmd_down() {
    echo ">>> Removing stack..."
    EXTERNAL_RESOURCES=true docker stack rm "${PROJECT_PREFIX}" || true

    echo ">>> Stopping dependencies..."
    docker compose \
        -p "${PROJECT_PREFIX}" -f docker-compose.yml \
        down -v --remove-orphans || true
}

case "$COMMAND" in
    up) cmd_up ;;
    down) cmd_down ;;
    *) echo "Unknown command: $COMMAND"; usage ;;
esac
