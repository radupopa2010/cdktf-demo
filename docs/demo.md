# Demo runbook

The live, in-front-of-the-room demo. ~8 minutes if everything's already deployed (which it is, after the pre-deploy you ran the night before).

> Pre-deploy is no longer in this file — it's a one-time setup that's already done. If you're starting from a fresh AWS account, do the steps in the README's "One-time bootstrap" section first.

## Setup before walking on stage

Open two terminals:

- **Wide terminal**: where you run commands
- **Narrow terminal**: tailing `gh run watch` so the room sees CI light up

Configure the local Cachix CLI with the same push token CI uses (sourced from AWS Secrets Manager — no token typed or pasted):

```bash
cachix authtoken "$(aws secretsmanager get-secret-value --profile radupopa \
  --region eu-central-1 --secret-id cdktf-demo/devnet/cachix-radupopa2010-token \
  --query SecretString --output text)"
```

Pre-warm the Cachix cache so the `app-build` job in CI is visibly fast:

```bash
nix build .#rust-demo .#rust-demo-image --print-out-paths \
  | cachix push radupopa2010
```

Save the ALB hostname so you don't have to derive it live:

```bash
ALB=$(aws elbv2 describe-load-balancers \
  --profile radupopa --region eu-central-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-rustdemo`)].DNSName' \
  --output text)
echo "$ALB"
```

## The 9 beats

### Beat 0 — "Here's what's live" (15 s)

```bash
curl "http://$ALB/version"
# → {"version":"0.1.X","commit":"<sha>"}
```

> "This is the version EKS is serving right now. We're going to bump it and watch the pipeline put a new one up — without anyone touching kubectl, terraform, or AWS."

### Beat 1 — Bump the version + commit locally (30 s)

```bash
$EDITOR app/Cargo.toml
# version = "0.1.X" → "0.1.(X+1)"
(cd app && cargo update --offline -p rust-demo)
git commit -am "app: bump to 0.1.X"
```

Commit locally but **don't push yet** — you validate first. The commit gives Nix a clean git tree (no "uncommitted changes" warning) and a clean commit sha in `/version` (not `<sha>-dirty`).

### Beat 2 — Build + validate locally with Nix (~60 s)

```bash
./scripts/dev-up.sh
```

What happens, narrated:

- `nix build .#rust-demo` — builds the native macOS binary (validates the code compiles)
- `nix build .#rust-demo-image` — builds the OCI image for the host arch
- Starts the native binary on `:8080`, polls `/health`, asserts `/version` matches `Cargo.toml`

> "The code compiles and serves the right version. Now let me also cross-compile the exact image CI will ship to ECR."

```bash
./scripts/dev-down.sh
```

### Beat 2b — Push to Cachix (feeds the macOS CI runner) (~10 s)

```bash
nix build .#rust-demo --print-out-paths | cachix push radupopa2010
```

What happens, narrated:

- Pushes the `aarch64-darwin` binary (and all its deps) to the shared Cachix cache.
- CI has a `validate-mac` job that runs on `macos-latest` (also Apple Silicon / aarch64-darwin). Same system = same derivation hashes = **full cache hit**.
- The CI macOS runner will finish in seconds instead of minutes because everything was already built on your laptop.

> "I just pushed my local build to Cachix. Watch the CI macOS job — it'll pull instead of compile. Same architecture, same Nix derivation, same hash. That's local feeding CI."

### Beat 3 — Push + cut the release (20 s)

```bash
git push origin main
git tag -a v0.1.X -m "v0.1.X"
git push origin v0.1.X
gh release create v0.1.X --generate-notes
gh run watch
```

> "From here, GitHub Actions does everything. Zero humans in the loop."

### Beat 4 — Watch CI use the cache (1–2 min)

In the narrow terminal, `gh run watch` shows `app-release` light up:

1. `resolve-tag` — extracts `v0.1.X` (~3 s)
2. `validate-mac` — runs on `macos-latest` (Apple Silicon, same arch as your laptop)
3. `build` — runs on `ubuntu-latest`, builds the native x86_64 OCI image + pushes to ECR

Open the **`validate-mac`** job's log. This is the cache-hit punchline:

```text
copying path '/nix/store/...' from 'https://radupopa2010.cachix.org'
```

> "The macOS CI runner is pulling every single artifact from Cachix — because I just built and pushed the exact same derivation from my laptop 90 seconds ago. Same Apple Silicon arch, same Nix inputs, same hash. That's local feeding CI."

**How to verify cache reuse:** compare the `validate-mac` job time (should be ~30s with cache) vs the `build` job time (~2 min, Linux cache from previous run). The Mac job is faster because YOUR local push fed it directly.

### Beat 5 — CI deploys (2–3 min)

`infra-tier-04-applications` calls the reusable `_infra-shared-cdktf-tier.yml`. `cdktf deploy devnet --var=image_tag=v0.1.X`. Helm release rolls out, AWS LBC updates target groups.

### Beat 6 — CI auto-validates with `smoke-test`

Final job: `aws eks update-kubeconfig`, then `./scripts/smoke-test.sh v0.1.X`. Polls the live ALB until `/version` equals the released tag. The Step Summary on the run page shows the live JSON in a fenced code block — point at the green ✅.

### Beat 7 — Confirm from your laptop (10 s)

```bash
curl "http://$ALB/version"
# → {"version":"0.1.X","commit":"<new-sha>"}
```

### Beat 8 (bonus) — "And here's the exact ECR bytes on my laptop" (30 s)

```bash
./scripts/dev-pull.sh v0.1.X
```

Pulls the v0.1.X image from ECR, runs it under Docker (Rosetta on Apple Silicon), curls `/version`.

> "The bits running here came from CI minutes ago. Bit-identical to what EKS is pulling. Nix made all three of them the same artifact."

## After the demo

Optional bump-and-rollback to show the pipeline in reverse:

```bash
git revert HEAD --no-edit
git push
git tag -a v0.1.(X-1)-revert -m "rollback"
git push origin v0.1.(X-1)-revert
gh release create v0.1.(X-1)-revert --generate-notes
```

Or save money by tearing devnet down for the night:

```bash
./scripts/destroy-all.sh
```

(Cluster destroy takes ~10 min. NAT + EKS together cost ~$3/day if left up.)

## Quick reference

```bash
# Local validation
./scripts/dev-up.sh                  # nix build + run native + assert version
./scripts/dev-up.sh --container      # OCI image via docker (Linux host or linux-builder)
./scripts/dev-pull.sh v0.1.X         # pull-and-run the exact ECR image

# Cloud validation (kubectl required)
./scripts/smoke-test.sh v0.1.X

# Multi-arch local build (requires linux-builder on macOS)
./scripts/dev-build-multi.sh

# Operations
gh workflow run infra-tier-XX-...yml
gh workflow run infra-deploy-all.yml -f confirm=devnet
gh release create v0.1.X --generate-notes
./scripts/destroy-all.sh
```

## Troubleshooting on stage

| Symptom | Likely cause | Quick fix |
|---|---|---|
| `dev-up.sh` says "version mismatch" | Forgot `cargo update` after bumping `Cargo.toml` | `(cd app && cargo update --offline -p rust-demo)` |
| `gh release create` fires no workflow | Tag already existed, GH ignored the duplicate trigger | Delete release + re-create: `gh release delete vX.Y.Z --yes && gh release create vX.Y.Z --generate-notes` |
| Smoke-test times out polling ALB | Two `app-release` runs raced for the state lock | Check `gh run list --status in_progress` — should be one. If two, kill the duplicate (concurrency should prevent this) |
| `/version` returns the old version after CI green | cdktf var flag wrong (`-var` vs `--var=`) | Already fixed in `infra-tier-04-applications.yml`; if it recurs, check the `extra_vars:` line |
| ALB DNS doesn't resolve | New release is mid-rollout, old ALB DNS may not be updated yet | Re-derive: `aws elbv2 describe-load-balancers ... --query '...DNSName'` |
