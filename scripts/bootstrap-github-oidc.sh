#!/usr/bin/env bash
# Create the AWS IAM OIDC provider for GitHub Actions and the
# `cdktf-demo-gha` role that workflows assume. Idempotent.
#
# Usage:
#   GITHUB_OWNER=integer-it GITHUB_REPO=cdktf-demo ./scripts/bootstrap-github-oidc.sh

set -euo pipefail

PROFILE="${AWS_PROFILE:-radupopa}"
REGION="${AWS_REGION:-eu-central-1}"

GITHUB_OWNER="${GITHUB_OWNER:-}"
GITHUB_REPO="${GITHUB_REPO:-cdktf-demo}"

if [ -z "$GITHUB_OWNER" ]; then
  read -rp "GitHub owner/org (e.g. integer-it): " GITHUB_OWNER
fi

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
ROLE_NAME="cdktf-demo-gha"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

echo "==> Bootstrapping GitHub OIDC for ${GITHUB_OWNER}/${GITHUB_REPO}"

# ── OIDC provider ────────────────────────────────────────────────────────
if aws iam get-open-id-connect-provider --profile "$PROFILE" \
     --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  echo "[oidc]  provider exists"
else
  echo "[oidc]  creating provider"
  aws iam create-open-id-connect-provider --profile "$PROFILE" \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
fi

# ── Trust policy ─────────────────────────────────────────────────────────
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "${PROVIDER_ARN}" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:${GITHUB_OWNER}/${GITHUB_REPO}:*" }
    }
  }]
}
EOF
)

if aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" >/dev/null 2>&1; then
  echo "[role]  exists — updating trust policy"
  aws iam update-assume-role-policy --profile "$PROFILE" \
    --role-name "$ROLE_NAME" \
    --policy-document "$TRUST_POLICY"
else
  echo "[role]  creating $ROLE_NAME"
  aws iam create-role --profile "$PROFILE" \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "GitHub Actions deployer for cdktf-demo"
fi

# ── Permissions (demo: AdministratorAccess; tighten in real life) ────────
echo "[role]  attaching AdministratorAccess (demo only — tighten later)"
aws iam attach-role-policy --profile "$PROFILE" \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

cat <<EOF

✅ OIDC + role ready.

Now configure the GitHub repo (Settings → Secrets and variables → Actions → Variables):
  AWS_ROLE_ARN       = ${ROLE_ARN}
  AWS_REGION         = ${REGION}
  CACHIX_CACHE_NAME  = radupopa2010

Note: these are repository VARIABLES, not secrets. There are no secrets in
this project's GitHub config — every secret lives in AWS Secrets Manager.

Next: scripts/bootstrap-secrets.sh
EOF
