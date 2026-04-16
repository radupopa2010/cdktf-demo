#!/usr/bin/env bash
# Tear down devnet in reverse tier order. set +e on each step so an
# already-deleted resource doesn't abort the rest.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV="${1:-devnet}"

if [ "$ENV" != "devnet" ]; then
  echo "Only 'devnet' supported. Got: $ENV" >&2
  exit 1
fi

destroy_tier() {
  local tier_dir="$1"
  echo ""
  echo "==> destroy ${tier_dir} (${ENV})"
  pushd "${ROOT}/${tier_dir}" >/dev/null || return 0
  set +e
  cdktf destroy "$ENV" --auto-approve \
    2>&1 | tee "logs/destroy-$(date -u +%Y%m%dT%H%M%SZ).log"
  set -e
  popd >/dev/null
}

destroy_tier "tier-04-cdktf-applications"
destroy_tier "tier-03-cdktf-internal-tools"
destroy_tier "tier-02-cdktf-clusters"
destroy_tier "tier-01-cdktf-environments"

echo ""
echo "✅ destroy-all complete (env=${ENV})"
