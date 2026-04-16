#!/usr/bin/env bash
# Local equivalent of the deploy-all.yml workflow. Use with care: this
# triggers real cloud resources. Prefer the CI workflow.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV="${1:-devnet}"
IMAGE_TAG="${2:-latest}"

if [ "$ENV" != "devnet" ]; then
  echo "Only 'devnet' supported in the demo. Got: $ENV" >&2
  exit 1
fi

apply_tier() {
  local tier_dir="$1"
  echo ""
  echo "==> deploy ${tier_dir} (${ENV})"
  pushd "${ROOT}/${tier_dir}" >/dev/null
  npm install
  cdktf get
  mkdir -p logs
  cdktf deploy "$ENV" --auto-approve "${@:2}" \
    2>&1 | tee "logs/deploy-$(date -u +%Y%m%dT%H%M%SZ).log"
  popd >/dev/null
}

apply_tier "tier-01-cdktf-environments"
apply_tier "tier-02-cdktf-clusters"
apply_tier "tier-03-cdktf-internal-tools"
apply_tier "tier-04-cdktf-applications" "-var" "image_tag=${IMAGE_TAG}"

echo ""
echo "✅ deploy-all complete (env=${ENV}, image_tag=${IMAGE_TAG})"
