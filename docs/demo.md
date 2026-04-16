# Demo runbook

The live, in-front-of-the-room demo. ~8 minutes if everything's already deployed (which it is, after the pre-deploy you ran the night before).

> Pre-deploy is no longer in this file — it's a one-time setup that's already done. If you're starting from a fresh AWS account, do the steps in the README's "One-time bootstrap" section first.

## Setup before walking on stage

Open two terminals:

- **Wide terminal**: where you run commands
- **Narrow terminal**: tailing `gh run watch` so the room sees CI light up

Pre-warm the Cachix cache from your laptop so the `app-build` job in CI is visibly fast on the demo:

```bash
nix build .#rust-demo .#rust-demo-image --print-out-paths \
  | cachix push radupopa2010
```

(Requires `cachix authtoken <your-token>` once. The token is the same one stored in AWS Secrets Manager for CI.)

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

### Beat 1 — Bump the version (20 s)

```bash
$EDITOR app/Cargo.toml
# version = "0.1.X" → "0.1.(X+1)"
```

Show the one-line diff in the editor. Then refresh the lockfile (deterministic, fast):

```bash
(cd app && cargo update --offline -p rust-demo)
```

### Beat 2 — Build + validate locally with Nix (30 s)

```bash
./scripts/dev-up.sh
```

What happens, narrated:

- `nix build .#rust-demo` — only the binary recompiles; every Rust dep comes from Cachix
- Starts the binary on `:8080`, polls `/health`, asserts `/version` matches `Cargo.toml`
- Built in ~30 s on a warm cache

> "30 seconds because Cachix already has every dependency. No need to push to find out it's broken."

```bash
./scripts/dev-down.sh
```

### Beat 3 — PR + merge (45 s)

```bash
git checkout -b bump-to-0.1.X
git commit -am "app: bump to 0.1.X"
git push -u origin bump-to-0.1.X
gh pr create --fill
gh pr merge --squash --delete-branch
```

> "Notice no tier workflow fired on push or merge — only app-only paths changed, the per-tier `paths:` filters didn't match. Releases are how you deploy."

### Beat 4 — Cut the release (20 s)

```bash
git checkout main && git pull
git tag -a v0.1.X -m "v0.1.X"
git push origin v0.1.X
gh release create v0.1.X --generate-notes
gh run watch
```

> "From here, GitHub Actions does everything. Zero humans in the loop."

### Beat 5 — Watch CI use the cache (1–2 min)

In the narrow terminal, `gh run watch` shows `app-release` light up:

1. `resolve-tag` — extracts `v0.1.X` (~3 s)
2. `build` — `nix build .#rust-demo-image` + `docker push` to ECR

Open the build job's log and grep mentally for:

```text
copying path '/nix/store/...' from 'https://radupopa2010.cachix.org'
```

> "Two punchlines on this screen. One: there are zero secrets in this repo's GitHub config — auth is OIDC, the Cachix token comes from AWS Secrets Manager. Two: every Rust dep is being pulled from cache, not recompiled. The build is the same Nix derivation we ran on my laptop 90 seconds ago."

### Beat 6 — CI deploys (2–3 min)

`tier-04-applications` calls the reusable `_shared-cdktf-tier.yml`. `cdktf deploy devnet --var=image_tag=v0.1.X`. Helm release rolls out, AWS LBC updates target groups.

### Beat 7 — CI auto-validates with `smoke-test`

Final job: `aws eks update-kubeconfig`, then `./scripts/smoke-test.sh v0.1.X`. Polls the live ALB until `/version` equals the released tag. The Step Summary on the run page shows the live JSON in a fenced code block — point at the green ✅.

### Beat 8 — Confirm from your laptop (10 s)

```bash
curl "http://$ALB/version"
# → {"version":"0.1.X","commit":"<new-sha>"}
```

### Beat 9 (bonus) — "And here's the exact ECR bytes on my laptop" (30 s)

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
gh workflow run tier-XX-...yml
gh workflow run deploy-all.yml -f confirm=devnet
gh release create v0.1.X --generate-notes
./scripts/destroy-all.sh
```

## Troubleshooting on stage

| Symptom | Likely cause | Quick fix |
|---|---|---|
| `dev-up.sh` says "version mismatch" | Forgot `cargo update` after bumping `Cargo.toml` | `(cd app && cargo update --offline -p rust-demo)` |
| `gh release create` fires no workflow | Tag already existed, GH ignored the duplicate trigger | Delete release + re-create: `gh release delete vX.Y.Z --yes && gh release create vX.Y.Z --generate-notes` |
| Smoke-test times out polling ALB | Two `app-release` runs raced for the state lock | Check `gh run list --status in_progress` — should be one. If two, kill the duplicate (concurrency should prevent this) |
| `/version` returns the old version after CI green | cdktf var flag wrong (`-var` vs `--var=`) | Already fixed in `tier-04-applications.yml`; if it recurs, check the `extra_vars:` line |
| ALB DNS doesn't resolve | New release is mid-rollout, old ALB DNS may not be updated yet | Re-derive: `aws elbv2 describe-load-balancers ... --query '...DNSName'` |
