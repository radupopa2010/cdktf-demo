#!/usr/bin/env bash
# Build the rust-demo OCI image for BOTH linux/amd64 and linux/arm64 from a
# single host. Useful when you want to push a multi-arch manifest to ECR or
# verify the artifact reproduces across platforms.
#
# Requirements:
#   - Linux host (x86_64 OR aarch64): you can build the matching arch
#     natively; the other arch requires either binfmt+qemu OR a remote
#     builder for that architecture.
#
#   - macOS host: requires nix-darwin's linux-builder enabled
#     (https://nixcademy.com/posts/macos-linux-builder/) — one-time setup.
#     Without it, you'll see "a 'x86_64-linux' with features ... is required
#     to build ..." and the build fails.
#
# Outputs:
#   result-linux-amd64 → linux/amd64 OCI tarball
#   result-linux-arm64 → linux/arm64 OCI tarball

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CYAN="\033[0;36m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RESET="\033[0m"
say() { printf "${CYAN}==>${RESET} %s\n" "$*"; }
ok()  { printf "${GREEN}✅ %s${RESET}\n" "$*"; }
warn(){ printf "${YELLOW}⚠️  %s${RESET}\n" "$*"; }

build_for() {
  local system="$1" out="$2"
  say "Building .#packages.${system}.rust-demo-image → ${out}"
  if ! nix build ".#packages.${system}.rust-demo-image" \
       --print-build-logs -o "$out"; then
    warn "Build for ${system} failed."
    case "$(uname -s)" in
      Darwin)
        warn "On macOS, cross-building Linux requires nix-darwin's linux-builder."
        warn "See https://nixcademy.com/posts/macos-linux-builder/ for one-time setup."
        ;;
      Linux)
        warn "On Linux, cross-arch builds need binfmt-misc + qemu OR a remote builder."
        warn "Try: sudo systemctl start systemd-binfmt (if using systemd)."
        ;;
    esac
    return 1
  fi
  ok "Built ${system}: $(readlink -f "$out")"
}

build_for "x86_64-linux"  result-linux-amd64
build_for "aarch64-linux" result-linux-arm64

cat <<EOF

Both images built. Inspect:
  docker load < result-linux-amd64
  docker load < result-linux-arm64

To push as a multi-arch ECR manifest (after \`docker login\`):
  docker tag rust-demo:latest <ECR>:<tag>-amd64
  docker tag rust-demo:latest <ECR>:<tag>-arm64
  docker push <ECR>:<tag>-amd64
  docker push <ECR>:<tag>-arm64
  docker manifest create <ECR>:<tag> <ECR>:<tag>-amd64 <ECR>:<tag>-arm64
  docker manifest push <ECR>:<tag>
EOF
