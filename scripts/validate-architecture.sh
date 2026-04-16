#!/usr/bin/env bash
# Architectural sanity checks.
#  - modules/ never reference other modules
#  - tiers never reference higher-numbered tiers
#  - no AWS_SECRET_ACCESS_KEY / passwords / tokens checked into tfvars
#  - every tier has a stack class and a synth-able main.ts

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERR=0

fail() { echo "❌ $*" >&2; ERR=1; }
ok()   { echo "✅ $*"; }

echo "==> validate-architecture"

# 1. Modules don't reference SIBLING modules (relative paths going UP and over).
#    Allowed: registry sources (terraform-aws-modules/...), child modules
#    inside the same module dir. Skips `.terraform/` (downloaded cache).
for tier in "$ROOT"/tier-*/; do
  for module in "$tier"/modules/*/; do
    if grep -rE --exclude-dir=.terraform 'source[[:space:]]*=[[:space:]]*"\.\./\.\./modules/' "$module" >/dev/null 2>&1; then
      fail "$module references a sibling module via relative path"
    fi
  done
done
ok "modules don't cross-reference"

# 2. Tiers don't reference higher-numbered tiers in remote_state keys
for tier in "$ROOT"/tier-*/; do
  this_n=$(basename "$tier" | sed -E 's/^tier-0?([0-9]+).*/\1/')
  if grep -rE 'tier-0?([0-9]+)' "$tier/src" 2>/dev/null \
       | grep -vE "tier-?0?${this_n}" \
       | awk -F'tier-0?' '{print $2}' \
       | awk '{print $1}' \
       | grep -E '^[0-9]+$' \
       | while read -r ref; do
           if [ "$ref" -gt "$this_n" ]; then
             fail "tier-${this_n} references higher tier-${ref}"
           fi
         done; then :; fi
done
ok "tiers don't reference higher-numbered tiers"

# 3. No obvious secret material in tfvars
if grep -rEi '(password|secret|token|api[_-]?key)' "$ROOT"/tier-*/terraform.*.tfvars.json 2>/dev/null \
     | grep -vE '"aws_profile"' >/dev/null; then
  fail "found secret-looking key in tfvars (use AWS Secrets Manager instead)"
else
  ok "no secret material in tfvars"
fi

# 4. Every tier has a synth-able main.ts and a stack file
for tier in "$ROOT"/tier-*/; do
  if [ ! -f "$tier/src/infra/main.ts" ]; then
    fail "$tier missing src/infra/main.ts"
  fi
  if ! ls "$tier/src/infra/stacks/"*.ts >/dev/null 2>&1; then
    fail "$tier has no stack files in src/infra/stacks/"
  fi
done
ok "every tier has main.ts + at least one stack"

if [ "$ERR" -ne 0 ]; then
  echo ""
  echo "validate-architecture FAILED"
  exit 1
fi
echo ""
echo "validate-architecture PASSED"
