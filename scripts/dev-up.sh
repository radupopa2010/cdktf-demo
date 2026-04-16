#!/usr/bin/env bash
# Build the rust-demo with Nix (Cachix-backed) and run it locally so you can
# curl /version before pushing. Default mode is the native binary — works on
# every host, including Apple Silicon. Use --container for the OCI flow
# (requires a Linux host OR a configured nix-darwin linux-builder, since
# `dockerTools` images carry the *host's* Linux binaries; macOS hosts produce
# Mach-O binaries inside a "linux" image, which docker won't exec).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CYAN="\033[0;36m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RESET="\033[0m"
say() { printf "${CYAN}==>${RESET} %s\n" "$*"; }
ok()  { printf "${GREEN}✅ %s${RESET}\n" "$*"; }
warn(){ printf "${YELLOW}⚠️  %s${RESET}\n" "$*"; }

MODE="${1:-native}"   # native | --container

case "$MODE" in
  native|--native|-n)
    MODE="native" ;;
  container|--container|-c)
    MODE="container" ;;
  *)
    echo "usage: $0 [native|--container]" >&2
    exit 2 ;;
esac

# ── Build the binary (native) or the OCI image (container) ───────────────
START=$(date +%s)
if [ "$MODE" = "native" ]; then
  say "Building rust-demo native binary with Nix (Cachix-backed)"
  nix build .#rust-demo --print-build-logs
  BIN="$(readlink -f result)/bin/rust-demo"
  ok "Built in $(( $(date +%s) - START ))s — $(readlink -f result)"
else
  say "Building rust-demo OCI image with Nix (Cachix-backed)"
  nix build .#rust-demo-image --print-build-logs
  ok "Built in $(( $(date +%s) - START ))s — store path: $(readlink -f result)"
fi

# ── Run it ───────────────────────────────────────────────────────────────
PIDFILE="$ROOT/.dev-up.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  warn "Previous dev-up still running (PID $(cat "$PIDFILE")); stopping it"
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

if [ "$MODE" = "native" ]; then
  say "Starting rust-demo (native binary, background)"
  RUST_LOG=info "$BIN" >/tmp/rust-demo.log 2>&1 &
  echo $! > "$PIDFILE"
  TEAR_DOWN_HINT="kill \$(cat $PIDFILE) && rm $PIDFILE"
else
  say "Loading image into local Docker"
  docker load < result | tail -1 | sed 's/^/    /'

  case "$(uname -m)" in
    arm64|aarch64) export DOCKER_PLATFORM=linux/arm64 ;;
    x86_64|amd64)  export DOCKER_PLATFORM=linux/amd64 ;;
  esac
  say "Starting docker compose (platform=${DOCKER_PLATFORM:-default})"
  docker compose -f app/docker-compose.yml up -d --force-recreate
  TEAR_DOWN_HINT="./scripts/dev-down.sh"
fi

# ── Poll /health ─────────────────────────────────────────────────────────
say "Waiting for /health on localhost:8080"
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
    ok "Up after ${i}s"
    break
  fi
  if [ "$i" = "30" ]; then
    warn "Never came up; tail of logs:"
    if [ "$MODE" = "native" ]; then
      tail -n 30 /tmp/rust-demo.log
    else
      docker compose -f app/docker-compose.yml logs --tail 30 rust-demo
    fi
    exit 1
  fi
  sleep 1
done

# ── Hit /version and assert ──────────────────────────────────────────────
say "GET /version"
RESP=$(curl -sf http://localhost:8080/version)
echo "    $RESP"

EXPECTED_VERSION=$(awk -F\" '/^version =/ {print $2; exit}' app/Cargo.toml)
ACTUAL_VERSION=$(echo "$RESP" | jq -r .version)

if [ "$ACTUAL_VERSION" = "$EXPECTED_VERSION" ]; then
  ok "Live version ($ACTUAL_VERSION) matches Cargo.toml ($EXPECTED_VERSION)"
else
  warn "Version mismatch: Cargo.toml=$EXPECTED_VERSION, runtime=$ACTUAL_VERSION"
  exit 1
fi

cat <<EOF

Mode: $MODE
Stop with: $TEAR_DOWN_HINT
EOF
