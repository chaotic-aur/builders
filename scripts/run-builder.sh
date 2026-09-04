#!/usr/bin/env bash
set -euo pipefail

export REDIS_PORT="${REDIS_PORT:-6379}"

isRunning() {
    if [ ! -f /tmp/tunnel.pid ]; then return 1; fi
    pid=$(cat /tmp/tunnel.pid)
    if [ ! -d /proc/"$pid" ]; then return 1; fi
    if [ "$(cat /proc/"$pid"/comm)" != "autossh" ]; then return 1; fi
    return 0
}

if [ -n "${REDIS_SSH_HOST:-}" ]; then
    REDIS_SSH_PORT="${REDIS_SSH_PORT:-270}"
    REDIS_SSH_USER="${REDIS_SSH_USER:-root}"

    if ! isRunning; then
        echo "Setting up autossh tunnel to $REDIS_SSH_USER@$REDIS_SSH_HOST:$REDIS_SSH_PORT -> 6380:127.0.0.1:${REDIS_PORT}"
        AUTOSSH_PIDFILE=/tmp/tunnel.pid AUTOSSH_GATETIME=0 AUTOSSH_PORT=0 autossh -f -N \
            -L "6380:127.0.0.1:${REDIS_PORT}" \
            -p "$REDIS_SSH_PORT" \
            -o StrictHostKeyChecking=no \
            -o ServerAliveInterval=60 \
            -o ServerAliveCountMax=3 \
            -o ExitOnForwardFailure=yes \
            -o ConnectTimeout=10 \
            -o TCPKeepAlive=yes \
            -i /app/sshkey \
            "$REDIS_SSH_USER@$REDIS_SSH_HOST"
    else
        echo "autossh already running"
    fi

    export REDIS_PORT=6380
    export REDIS_HOST="${REDIS_HOST:-127.0.0.1}"

    echo "Waiting for tunnel localhost:$REDIS_PORT ..."
    for i in $(seq 1 30); do
        if nc -z localhost "$REDIS_PORT" 2>/dev/null; then
            echo "Tunnel established"
            break
        fi
        sleep 1
        if [ "$i" -eq 30 ]; then
            echo "Tunnel failed to establish after 30s" >&2
            exit 1
        fi
    done
else
    REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
    export REDIS_HOST
    echo "Checking Redis $REDIS_HOST:$REDIS_PORT ..."
    for i in $(seq 1 10); do
        if nc -z "$REDIS_HOST" "$REDIS_PORT" 2>/dev/null; then
            echo "Redis reachable"
            break
        fi
        sleep 1
        if [ "$i" -eq 10 ]; then
            echo "Redis not reachable at $REDIS_HOST:$REDIS_PORT (REDIS_SSH_HOST empty, no tunnel) — check secrets REDIS_SSH_HOST/REDIS_HOST/REDIS_PORT" >&2
            exit 1
        fi
    done
fi

SHARED_PATH="${SHARED_PATH:-/tmp/shared}"
mkdir -p "$SHARED_PATH"/{pkgout,sources,temp,srcdest_cache}
chown 1000:1000 "$SHARED_PATH"/pkgout "$SHARED_PATH"/build 2>/dev/null || true
if [ -n "${BUILDER_BUILD_DIR_HOST:-}" ] && [ ! -d "$BUILDER_BUILD_DIR_HOST" ]; then
    mkdir -p "$BUILDER_BUILD_DIR_HOST"
    chown 1000:1000 "$BUILDER_BUILD_DIR_HOST" 2>/dev/null || true
fi

RUNTIME="${BUILDER_RUNTIME:-340m}"
echo "Starting builder for $RUNTIME (host=$BUILDER_HOSTNAME, class=${BUILDER_CLASS:-2})"
echo "Redis target $REDIS_HOST:${REDIS_PORT:-6379} via ${REDIS_SSH_HOST:-direct}"

UP_HOST="${DATABASE_HOST:-${DATABASE_HOST_UP:-builds.garudalinux.org}}"
UP_PORT="${DATABASE_PORT:-210}"
UP_USER="${DATABASE_USER:-package-deployer}"
if nc -z -w 5 "$UP_HOST" "$UP_PORT" 2>/dev/null; then
    echo "Upload SSH reachable $UP_HOST:$UP_PORT"
    if printf 'pwd\n' | sftp -i /app/sshkey -P "$UP_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 "$UP_USER@$UP_HOST" 2>&1; then
        echo "Upload SFTP auth OK ($UP_USER@$UP_HOST:$UP_PORT)"
    else
        echo "Upload SFTP auth FAIL ($UP_USER@$UP_HOST:$UP_PORT) key=/app/sshkey" >&2
    fi
else
    echo "Upload SSH UNREACHABLE $UP_HOST:$UP_PORT" >&2
fi

if command -v timeout >/dev/null 2>&1; then
    timeout "$RUNTIME" node /app/index.mjs builder >/dev/null 2>&1 || code=$?
else
    node /app/index.mjs builder >/dev/null 2>&1 || code=$?
fi
code=${code:-0}
case "$code" in 124|143|137)
    echo "Builder runtime expired (timeout $RUNTIME) — clean exit for retrigger"
    exit 0
    ;;
esac
exit "$code"
