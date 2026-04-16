#!/usr/bin/env bash
# Set values for the secrets created by tier-02's aws-secrets module.
#
# Tier-02 already creates the secret SHELLS via `null_resource` + `aws cli`;
# this script only puts the VALUES so they never enter Terraform state.
#
# Re-run any time a token rotates.

set -euo pipefail

PROFILE="${AWS_PROFILE:-radupopa}"
REGION="${AWS_REGION:-eu-central-1}"

put_secret() {
  local name="$1"
  local value="$2"
  echo "[secrets] put ${name}"
  aws --profile "$PROFILE" --region "$REGION" \
    secretsmanager put-secret-value \
    --secret-id "$name" \
    --secret-string "$value" >/dev/null
}

echo "==> Setting secret values in AWS Secrets Manager"
echo "    Tier-02 must have already been deployed (creates the secret shells)."
echo ""

# Cachix push token for cache `radupopa2010`.
echo "Generate at https://app.cachix.org/personal-auth-tokens"
read -rsp "CACHIX_AUTH_TOKEN (cache radupopa2010): " CACHIX_AUTH_TOKEN
echo ""
put_secret "cdktf-demo/devnet/cachix-radupopa2010-token" "$CACHIX_AUTH_TOKEN"

# Add more put_secret calls here as the inventory grows.

echo ""
echo "✅ Secrets populated."
