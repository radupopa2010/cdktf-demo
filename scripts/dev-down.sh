#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
docker compose -f app/docker-compose.yml down --remove-orphans
echo "✅ stopped"
