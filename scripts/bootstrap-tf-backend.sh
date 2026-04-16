#!/usr/bin/env bash
# Create the S3 bucket + DynamoDB lock table that all tiers use as their
# Terraform backend. Idempotent — safe to re-run.

set -euo pipefail

PROFILE="${AWS_PROFILE:-radupopa}"
REGION="${AWS_REGION:-eu-central-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
BUCKET="${CDKTF_STATE_BUCKET:-cdktf-demo-tfstate-${ACCOUNT_ID}}"
TABLE="${CDKTF_STATE_LOCK_TABLE:-cdktf-demo-tfstate-lock}"

echo "==> Bootstrapping TF backend"
echo "    profile : $PROFILE"
echo "    region  : $REGION"
echo "    bucket  : $BUCKET"
echo "    table   : $TABLE"

# ── S3 bucket ────────────────────────────────────────────────────────────
if aws s3api head-bucket --bucket "$BUCKET" --profile "$PROFILE" 2>/dev/null; then
  echo "[s3]      bucket exists"
else
  echo "[s3]      creating $BUCKET"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --profile "$PROFILE"
  else
    aws s3api create-bucket --bucket "$BUCKET" --profile "$PROFILE" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" --profile "$PROFILE" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET" --profile "$PROFILE" \
  --server-side-encryption-configuration '{
    "Rules": [{ "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" } }]
  }'

aws s3api put-public-access-block --bucket "$BUCKET" --profile "$PROFILE" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ── DynamoDB lock table ──────────────────────────────────────────────────
if aws dynamodb describe-table --table-name "$TABLE" --profile "$PROFILE" \
     --region "$REGION" >/dev/null 2>&1; then
  echo "[dynamo]  table exists"
else
  echo "[dynamo]  creating $TABLE"
  aws dynamodb create-table --profile "$PROFILE" --region "$REGION" \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
  aws dynamodb wait table-exists --profile "$PROFILE" --region "$REGION" \
    --table-name "$TABLE"
fi

cat <<EOF

✅ TF backend ready.

Export these in your shell (or in CI):
  export CDKTF_STATE_BUCKET=$BUCKET
  export CDKTF_STATE_LOCK_TABLE=$TABLE
  export AWS_REGION=$REGION

Next: scripts/bootstrap-github-oidc.sh
EOF
