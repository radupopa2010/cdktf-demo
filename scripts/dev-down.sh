#!/usr/bin/env bash
# Tear down whatever dev-up.sh started — native binary or container.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PIDFILE="$ROOT/.dev-up.pid"
if [ -f "$PIDFILE" ]; then
  PID="$(cat "$PIDFILE")"
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "stopped native rust-demo (pid $PID)"
  fi
  rm -f "$PIDFILE"
fi

# Always try to bring compose down too — harmless if it wasn't up.
docker compose -f app/docker-compose.yml down --remove-orphans 2>/dev/null || true

echo "✅ stopped"
