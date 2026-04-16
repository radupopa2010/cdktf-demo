#!/usr/bin/env bash
# Fetch the canonical AWS Load Balancer Controller IAM policy and overwrite
# the stub in tier-03. Run this once before the first tier-03 deploy, and
# periodically to pick up new permissions.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/tier-03-cdktf-internal-tools/modules/kubernetes-aws-load-balancer-controller/iam-policy.json"
URL="https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"

echo "==> Fetching $URL"
curl -fsSL "$URL" -o "$DEST.tmp"
mv "$DEST.tmp" "$DEST"
echo "✅ Wrote $DEST"
