#!/usr/bin/env bash
# Start minikube and apply the rust-demo manifests. For infra folk who want
# to iterate locally without touching AWS.

set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-cdktf-demo}"

if ! command -v minikube >/dev/null; then
  echo "minikube not installed. Install with: brew install minikube" >&2
  exit 1
fi

echo "==> Starting minikube profile $PROFILE"
minikube start \
  --profile "$PROFILE" \
  --cpus=4 \
  --memory=6g \
  --addons=ingress \
  --kubernetes-version=v1.30.0

echo "==> Building rust-demo image inside minikube's docker"
eval "$(minikube -p "$PROFILE" docker-env)"
docker compose -f "$(dirname "$0")/../app/docker-compose.yml" build

echo "==> Applying manifests"
kubectl apply -k "$(dirname "$0")/manifests/"

echo ""
echo "✅ Up. Visit:"
minikube -p "$PROFILE" service rust-demo --url
