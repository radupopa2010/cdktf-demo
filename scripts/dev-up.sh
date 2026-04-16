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

# ── Build both the binary AND the OCI image ──────────────────────────────
# The binary is what we run locally for validation.
# The OCI image is what CI builds and pushes to ECR. Building it here too
# means Cachix gets the derivation cached → CI's `nix build .#rust-demo-image`
# is a cache hit. On macOS we can't docker-run the image (it's a Mach-O binary
# inside a linux image → exec format error), but building it is the point:
# same Nix derivation, same cache, same artifact CI ships.
START=$(date +%s)
say "Building rust-demo binary + OCI image with Nix (Cachix-backed)"
nix build .#rust-demo --print-build-logs
BIN="$(readlink -f result)/bin/rust-demo"
nix build .#rust-demo-image --print-build-logs -o result-image
ok "Built in $(( $(date +%s) - START ))s"
say "Binary: $(readlink -f result)"
say "Image:  $(readlink -f result-image)"

if [ "$MODE" = "container" ]; then
  say "Loading OCI image into local Docker"
  docker load < result-image | tail -1 | sed 's/^/    /'
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
