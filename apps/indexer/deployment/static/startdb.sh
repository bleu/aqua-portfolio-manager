#!/usr/bin/env bash

# Allow overriding max_connections, default 150
POSTGRES_MAX_CONNECTIONS="${POSTGRES_MAX_CONNECTIONS:-150}"

# Determine total available RAM in MB
if [ -n "${POSTGRES_MEMORY_LIMIT:-}" ]; then
    # Use numfmt to convert to bytes, then to MB
    LIMIT_BYTES=$(numfmt --from=iec "${POSTGRES_MEMORY_LIMIT}" 2>/dev/null)
    if [ -z "$LIMIT_BYTES" ] || [ "$LIMIT_BYTES" = "0" ]; then
        echo "Error: Invalid POSTGRES_MEMORY_LIMIT value: $POSTGRES_MEMORY_LIMIT" >&2
        exit 1
    fi
    TOTAL_RAM_MB=$((LIMIT_BYTES / 1024 / 1024))
else
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
fi

# Calculations
SHARED_BUFFERS_MB=$((TOTAL_RAM_MB * 20 / 100))         # 20%
MAINTENANCE_WORK_MEM_MB=$((TOTAL_RAM_MB * 5 / 100))    # 5%
EFFECTIVE_CACHE_SIZE_MB=$((TOTAL_RAM_MB / 2))          # 50%
WORK_MEM_MB=$(( (TOTAL_RAM_MB * 25 / 100) / POSTGRES_MAX_CONNECTIONS )) # 25% divided by max connections

# Ensure minimums
if [ "$WORK_MEM_MB" -lt 1 ]; then WORK_MEM_MB=1; fi

set -x
exec docker-entrypoint.sh \
    -c "max_connections=${POSTGRES_MAX_CONNECTIONS}" \
    -c "shared_buffers=${SHARED_BUFFERS_MB}MB" \
    -c "work_mem=${WORK_MEM_MB}MB" \
    -c "maintenance_work_mem=${MAINTENANCE_WORK_MEM_MB}MB" \
    -c "effective_cache_size=${EFFECTIVE_CACHE_SIZE_MB}MB" \
    -c "max_wal_size=4GB" \
    -c "min_wal_size=1GB" \
    -c "checkpoint_completion_target=0.9" \
    -c "checkpoint_timeout=30min" \
    -c "wal_buffers=16MB"
