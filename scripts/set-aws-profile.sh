#!/usr/bin/env bash
# Source this from your shell to point AWS at the demo:
#   source scripts/set-aws-profile.sh
#
# Idempotent.

export AWS_PROFILE=radupopa
export AWS_REGION=eu-central-1
export CDKTF_STATE_BUCKET="${CDKTF_STATE_BUCKET:-cdktf-demo-tfstate-$(aws sts get-caller-identity --profile radupopa --query Account --output text 2>/dev/null || echo unknown)}"
export CDKTF_STATE_LOCK_TABLE="${CDKTF_STATE_LOCK_TABLE:-cdktf-demo-tfstate-lock}"

echo "AWS_PROFILE=$AWS_PROFILE  AWS_REGION=$AWS_REGION"
echo "CDKTF_STATE_BUCKET=$CDKTF_STATE_BUCKET"
echo "CDKTF_STATE_LOCK_TABLE=$CDKTF_STATE_LOCK_TABLE"
