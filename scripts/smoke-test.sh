#!/usr/bin/env bash
# Validate that the live deployment in EKS responds with the expected version.
# Used by CI (app-release workflow's smoke-test job) AND by humans from a
# laptop after a deploy.
#
# Usage:
#   ./scripts/smoke-test.sh v0.1.1     # poll until /version == "0.1.1"
#   ./scripts/smoke-test.sh 0.1.1      # same; leading 'v' is stripped
#
# Prereqs:
#   - kubectl configured against the demo cluster
#     (`aws eks update-kubeconfig --name cdktf-demo-devnet --region eu-central-1`)
#   - jq, curl

set -euo pipefail

EXPECTED="${1:?usage: smoke-test.sh <expected-version (e.g. v0.1.1)>}"
EXPECTED="${EXPECTED#v}"   # strip leading v
NS="${RUST_DEMO_NAMESPACE:-rust-demo}"
# Helm names the Ingress <release>-<chart> = rust-demo-rust-demo by default.
ING="${RUST_DEMO_INGRESS:-rust-demo-rust-demo}"

CYAN="\033[0;36m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RED="\033[0;31m"; RESET="\033[0m"

# ── 1. Resolve ALB hostname (Ingress is provisioned by AWS LB Controller) ──
# Once the Ingress exists, kubectl returns the hostname immediately. We only
# poll to absorb the case where the Helm release is mid-roll. 60 attempts ×
# 4s = 4 min ceiling — comfortable for a freshly-provisioned ALB.
printf "${CYAN}==>${RESET} Resolving ALB hostname for Ingress %s/%s\n" "$NS" "$ING"
ALB=""
LAST_ERR=""
for i in $(seq 1 60); do
  if ! ALB=$(kubectl get ing "$ING" -n "$NS" \
       -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>&1); then
    LAST_ERR="$ALB"
    ALB=""
  fi
  if [ -n "$ALB" ]; then break; fi
  printf "    waiting for ALB hostname (%d/60) — last err: %s\n" "$i" "${LAST_ERR:-empty}"
  sleep 4
done

if [ -z "$ALB" ]; then
  printf "${RED}❌ ALB hostname never appeared on Ingress %s/%s${RESET}\n" "$NS" "$ING"
  echo "   Likely causes: AWS LB Controller (tier-03) not running, or"
  echo "   public/private subnet tags missing in tier-01."
  exit 1
fi
printf "    ALB: ${YELLOW}http://%s${RESET}\n" "$ALB"

# ── 2. Wait for DNS to resolve and ALB to be healthy ──────────────────────
printf "${CYAN}==>${RESET} Waiting for ALB to start serving (DNS + targets healthy)\n"
for i in $(seq 1 30); do
  if curl -sf -m 5 "http://$ALB/health" >/dev/null 2>&1; then
    printf "    /health 200 after attempt %d\n" "$i"
    break
  fi
  if [ "$i" = "30" ]; then
    printf "${RED}❌ ALB never became healthy${RESET}\n"
    exit 1
  fi
  sleep 10
done

# ── 3. Poll /version until it matches expected ────────────────────────────
printf "${CYAN}==>${RESET} Polling /version until it equals %s\n" "$EXPECTED"
for i in $(seq 1 30); do
  RESP=$(curl -fsS -m 5 "http://$ALB/version" 2>/dev/null || true)
  VER=$(echo "$RESP" | jq -r .version 2>/dev/null || echo "")
  if [ "$VER" = "$EXPECTED" ]; then
    printf "\n${GREEN}✅ Live: %s${RESET}\n" "$RESP"
    printf "${GREEN}   ALB:  http://%s${RESET}\n\n" "$ALB"
    exit 0
  fi
  printf "    got '%s', want '%s' (attempt %d/30)\n" "$VER" "$EXPECTED" "$i"
  sleep 10
done

printf "${RED}❌ Never observed version %s on http://%s${RESET}\n" "$EXPECTED" "$ALB"
echo "   Last response: $RESP"
exit 1
