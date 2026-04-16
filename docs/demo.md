# Demo runbook

The end-to-end story this repo is built to tell — split into what to do **tonight** (everything that's slow / interactive / risky to do live) and what to do **tomorrow in front of the room** (everything that's fast and visually satisfying).

Skim once before you do either. Both halves assume the bootstrap section in [`../README.md`](../README.md) is already done (TF state backend, OIDC role, repo variables).

---

## Tonight — pre-deploy + smoke test (≈ 30 min wall-clock)

Goal: by the time you go to bed, devnet is live with `v0.1.0` deployed, the ALB is responding, and you've already curled it once. The morning is just bumping a version and watching cache hits.

### 0. Get a fresh shell

```bash
cd /Users/radupopa/p/radu/random-code/cdktf-demo
direnv allow      # or: nix develop
aws sts get-caller-identity --profile radupopa   # confirm fresh AWS session
```

### 1. Tier-01 (VPC) — ~3 min

```bash
gh workflow run tier-01-environments.yml
gh run watch
```

✅ when green and the cdktf step shows `Apply complete! Resources: ~24 added`.

### 2. Tier-02 (EKS + ECR + secret shells) — ~20 min ☕

```bash
gh workflow run tier-02-clusters.yml
gh run watch
```

EKS control plane = ~12 min, node group = ~5 min. Verify when done:

```bash
aws eks update-kubeconfig --profile radupopa --region eu-central-1 --name cdktf-demo-devnet
kubectl get nodes                                    # 1 t3.small, Ready
aws secretsmanager describe-secret --profile radupopa \
  --secret-id cdktf-demo/devnet/cachix-radupopa2010-token   # shell exists, no value
```

### 3. Put the Cachix push token in Secrets Manager

```bash
./scripts/bootstrap-secrets.sh
# Paste the token from https://app.cachix.org/personal-auth-tokens
# (cache: radupopa2010, scope: write).
```

This is the only time you ever interactively type a secret value. From here on, CI loads it via `aws secretsmanager get-secret-value` after the OIDC step.

### 4. Refresh the LBC IAM policy + Tier-03 (LBC) — ~5 min

```bash
./scripts/refresh-lbc-policy.sh
git add tier-03-cdktf-internal-tools/modules/kubernetes-aws-load-balancer-controller/iam-policy.json
git commit -m "tier-03: refresh LBC IAM policy"
git push
gh workflow run tier-03-internal-tools.yml
gh run watch
```

✅ when `kubectl get pods -n kube-system | grep aws-load-balancer-controller` shows 2 pods Running.

### 5. Pre-warm Cachix (the demo magic happens here)

This step is what makes tomorrow's CI build *fast*. Build the image locally now and push every transitive dep to Cachix; CI will fetch instead of compiling.

```bash
cachix authtoken <your-personal-token>
nix build .#rust-demo .#rust-demo-image --print-out-paths \
  | cachix push radupopa2010
```

(This can run while tier-02 is still cooking.)

### 6. Cut v0.1.0 — full pipeline runs

```bash
git tag -a v0.1.0 -m "first cdktf-demo release"
git push origin v0.1.0
gh release create v0.1.0 --generate-notes
gh run watch
```

`app-release.yml` chains: `resolve-tag → app-build → tier-04 deploy → smoke-test`. The `smoke-test` job at the end runs `./scripts/smoke-test.sh v0.1.0` and writes the live JSON to `$GITHUB_STEP_SUMMARY` — that summary is your "tonight worked" receipt.

### 7. Final manual confirm

```bash
ALB=$(kubectl get ing rust-demo -n rust-demo \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: http://$ALB"
curl "http://$ALB/version"
# → {"version":"0.1.0","commit":"<sha>"}
```

Save that ALB hostname for tomorrow (or just re-derive it from `kubectl`).

**State you'll wake up to:** devnet running v0.1.0, ALB green, Cachix populated, no GitHub secrets, all CI jobs green.

---

## Tomorrow — the demo (≈ 8 min)

Tight script. Each beat states what you're showing and why it matters. Have two terminals open: a wide one for commands, a smaller one tailing `gh run watch`.

### Beat 0 — "Here's what's live" (15s)

```bash
ALB=$(kubectl get ing rust-demo -n rust-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$ALB/version"
# → {"version":"0.1.0","commit":"<sha>"}
```

> "This is what was deployed last night. We're going to bump it and watch the pipeline put a new version up."

### Beat 1 — Bump the version (20s)

```bash
$EDITOR app/Cargo.toml
# Change version = "0.1.0" → "0.1.1"
```

Show the one-line diff in the editor.

### Beat 2 — Build + validate locally with Nix (30s, fast because Cachix)

```bash
./scripts/dev-up.sh
# nix build .#rust-demo (mostly cache hits)
# starts the binary, polls /health, asserts /version == 0.1.1
```

> "30 seconds to build because Cachix already has every dep. The script asserts the new version actually serves — no need to push to find out it's broken."

```bash
./scripts/dev-down.sh
```

### Beat 3 — Open + merge a PR (45s)

```bash
git checkout -b bump-to-0.1.1
git commit -am "app: bump to 0.1.1"
git push -u origin bump-to-0.1.1
gh pr create --fill
# (optional: show that no tier workflow fires for an app-only change)
gh pr merge --squash --delete-branch
```

### Beat 4 — Cut the release (20s)

```bash
git checkout main && git pull
git tag -a v0.1.1 -m "0.1.1: just the version, that's the point"
git push origin v0.1.1
gh release create v0.1.1 --generate-notes
gh run watch
```

> "From here, GitHub Actions does everything. No human in the loop."

### Beat 5 — Watch CI use the cache (1-2 min)

While the workflow runs, point at the `app-build` job's logs. Grep mentally for:

```text
copying path '/nix/store/...' from 'https://radupopa2010.cachix.org'
```

> "Two punchlines on this screen: there are zero secrets in this repo's GitHub config — auth is OIDC. And every Rust dep is coming from the Cachix cache, not being recompiled. Same artifact CI built last night, same store path."

### Beat 6 — Watch CI deploy (2-3 min)

`tier-04-applications` runs `cdktf deploy` with `image_tag=v0.1.1`. Helm release lands, ALB rolls.

### Beat 7 — CI auto-validates with smoke-test

The final `smoke-test` job runs `./scripts/smoke-test.sh v0.1.1`. Expand its summary on the workflow run page — green ✅ box with the live JSON.

### Beat 8 — Confirm from your laptop (10s)

```bash
curl "http://$ALB/version"
# → {"version":"0.1.1","commit":"<new-sha>"}
```

### Beat 9 (bonus, if there's time) — "And here's the exact ECR bytes on my laptop"

```bash
./scripts/dev-pull.sh v0.1.1
# logs into ECR, pulls the image CI just pushed, runs it under Docker
# (Rosetta on Apple Silicon), curls /version → 0.1.1
```

> "The bits running here are the bits CI pushed to ECR are the bits EKS pulled. Nix made all three of them the same artifact."

---

## After the demo — tear down (saves money)

```bash
./scripts/destroy-all.sh
# Reverse tier order: tier-04 → tier-03 → tier-02 → tier-01.
# Safe to re-run; failures don't cascade (set +e per tier).
```

Or just `kubectl delete ns rust-demo` if you want to keep the cluster running for next time.

---

## Quick reference — the key commands

```bash
# Validation
./scripts/dev-up.sh                  # local build + run + assert version (native)
./scripts/dev-up.sh --container      # same, in docker (needs Linux host or linux-builder)
./scripts/dev-pull.sh v0.1.1         # pull-and-run the exact ECR image
./scripts/smoke-test.sh v0.1.1       # poll live ALB until /version matches

# Multi-arch local build (requires linux-builder on macOS)
./scripts/dev-build-multi.sh         # builds linux/amd64 + linux/arm64

# Operations
gh workflow run tier-01-environments.yml
gh workflow run deploy-all.yml -f confirm=devnet
gh release create v0.1.X --generate-notes
./scripts/destroy-all.sh
```
