#!/usr/bin/env bash
# Pull the rust-demo image that CI just pushed to ECR and run it locally
# under docker compose. This is the "same bits as cloud" validation that
# works on every host (including Apple Silicon — Docker Desktop's Rosetta
# emulates the amd64 image transparently).
#
# Usage:
#   ./scripts/dev-pull.sh v0.1.0     # pulls and runs that exact tag

set -euo pipefail

TAG="${1:?usage: dev-pull.sh <tag, e.g. v0.1.0>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROFILE="${AWS_PROFILE:-radupopa}"
REGION="${AWS_REGION:-eu-central-1}"
REPO_NAME="${ECR_REPO_NAME:-cdktf-demo/rust-demo}"

CYAN="\033[0;36m"; GREEN="\033[0;32m"; RESET="\033[0m"
say() { printf "${CYAN}==>${RESET} %s\n" "$*"; }
ok()  { printf "${GREEN}✅ %s${RESET}\n" "$*"; }

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${REPO_NAME}:${TAG}"

say "Logging into ECR (${REGISTRY})"
aws ecr get-login-password --profile "$PROFILE" --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

say "Pulling ${IMAGE}"
docker pull "$IMAGE"

say "Re-tagging as rust-demo:latest so docker-compose picks it up"
docker tag "$IMAGE" rust-demo:latest

say "Starting docker compose (Rosetta on Apple Silicon, native on x86)"
export DOCKER_PLATFORM=linux/amd64
docker compose -f app/docker-compose.yml up -d --force-recreate

say "Waiting for /health on localhost:8080"
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
    ok "Up after ${i}s"
    break
  fi
  if [ "$i" = "30" ]; then
    docker compose -f app/docker-compose.yml logs --tail 30 rust-demo
    exit 1
  fi
  sleep 1
done

say "GET /version (the exact bits CI built and EKS is running)"
RESP=$(curl -sf http://localhost:8080/version)
echo "    $RESP"
ok "If this matches what \`./scripts/smoke-test.sh ${TAG}\` shows for the live ALB, the bits are identical."

cat <<EOF

Stop with: ./scripts/dev-down.sh
EOF
