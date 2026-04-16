#!/usr/bin/env bash
# Build the rust-demo OCI image with Nix (pulling from Cachix where possible),
# load it into the local Docker daemon, run it via docker-compose, and curl
# /version to prove the bits work.
#
# This is the "same artifact local and cloud" validation step in the demo:
# the image you run here is the SAME Nix derivation CI builds and pushes to
# ECR. Bit-identical, modulo CPU arch — see note at the bottom.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CYAN="\033[0;36m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RESET="\033[0m"
say() { printf "${CYAN}==>${RESET} %s\n" "$*"; }
ok()  { printf "${GREEN}✅ %s${RESET}\n" "$*"; }
warn(){ printf "${YELLOW}⚠️  %s${RESET}\n" "$*"; }

# ── 1. Build the OCI image with Nix ──────────────────────────────────────
say "Building rust-demo OCI image with Nix (Cachix-backed)"
START=$(date +%s)
nix build .#rust-demo-image --print-build-logs
ELAPSED=$(( $(date +%s) - START ))
STORE_PATH=$(readlink -f result)
ok "Built in ${ELAPSED}s — store path: $STORE_PATH"

# ── 2. Load into local Docker ────────────────────────────────────────────
say "Loading image into local Docker"
LOADED=$(docker load < result | tail -1)
echo "    $LOADED"

# ── 3. Start the container ───────────────────────────────────────────────
say "Starting docker compose"
docker compose -f app/docker-compose.yml up -d --force-recreate

# ── 4. Wait for /health ──────────────────────────────────────────────────
say "Waiting for /health on localhost:8080"
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
    ok "Up after ${i}s"
    break
  fi
  if [ "$i" = "30" ]; then
    warn "Never came up; tail of container logs:"
    docker compose -f app/docker-compose.yml logs --tail 30 rust-demo
    exit 1
  fi
  sleep 1
done

# ── 5. Hit /version and print ────────────────────────────────────────────
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

# ── 6. Note on parity with cloud ─────────────────────────────────────────
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
  arm64|aarch64)
    cat <<EOF

${YELLOW}Note on local↔cloud parity:${RESET}
  Your host is arm64. The image you just ran is the arm64 build of the same
  Nix derivation CI builds. CI runs on amd64 (ubuntu-latest), so the bytes
  inside the binary differ in CPU instructions, but every other input is
  identical (toolchain, deps, source tree). To get bit-for-bit identical
  artifacts on Apple Silicon, build with --system x86_64-linux (uses Rosetta
  or qemu) — slower, only worth it if you need to debug an arch-specific bug.

EOF
    ;;
esac

cat <<EOF

Stop with: ./scripts/dev-down.sh   (or: docker compose -f app/docker-compose.yml down)
EOF
