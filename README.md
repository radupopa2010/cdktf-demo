# cdktf-demo

A small but realistic demo of the multi-tier CDKTF pattern I used in the past, scaled down to one environment (`devnet`), one AWS region (`eu-central-1`), and one tiny Rust app on EKS. Built with Nix + Cachix for reproducible local & CI builds, deployed via GitHub Actions using OIDC + AWS Secrets Manager (no GitHub-stored secrets).

---

<details>
<summary><b>What's in here</b></summary>

```text
.
├── tier-01-cdktf-environments/      # VPC + subnets + NAT (calls terraform-aws-modules/vpc/aws)
├── tier-02-cdktf-clusters/          # EKS + dedicated nodegroup + ECR + Secrets Manager skeleton
├── tier-03-cdktf-internal-tools/    # AWS Load Balancer Controller (+ optional cert-manager)
├── tier-04-cdktf-applications/      # Helm release of the rust-demo app
├── app/                             # Rust + axum demo service, Helm chart, docker-compose
├── flake.nix                        # Reproducible Rust toolchain + OCI image, Cachix-cached
├── .github/workflows/               # One workflow per tier + orchestrator + app-release
├── scripts/                         # Bootstrap + dev-up + smoke-test + destroy-all helpers
├── docs/demo.md                     # Tonight + tomorrow demo script
└── .claude/skills/                  # Per-tier AI skills + cdktf safety + workflow trigger
```

</details>

<details>
<summary><b>Workflow execution model — what runs in what order</b></summary>

The Actions sidebar lists workflows alphabetically (`app-build`, `app-release`, `deploy-all`, then the tiers). That's *not* the execution order. The real relationships are by `uses:` (reusable invocation) and `needs:` (job dependency). There are seven workflow files split into three groups:

```text
┌─ REUSABLE — only invoked via workflow_call, never directly
│   _infra-shared-cdktf-tier.yml         plan + apply for one cdktf tier
│   app-build.yml                  nix build + cachix push + ECR push
│
├─ PER-TIER — each is a thin wrapper around _infra-shared-cdktf-tier.yml
│   infra-tier-01-environments.yml       VPC tier
│   infra-tier-02-clusters.yml           EKS + ECR + Secrets Manager
│   infra-tier-03-internal-tools.yml     LBC + cert-manager
│   infra-tier-04-applications.yml       Helm release of rust-demo
│
└─ TOP-LEVEL ORCHESTRATORS — what humans actually trigger
    infra-deploy-all.yml                 manual, full infra provision
    app-release.yml                release-driven, app-only redeploy
```

Two distinct flows in practice:

### Flow A — Infrastructure deploy (rare)

```text
gh workflow run infra-deploy-all.yml -f confirm=devnet
       │
       ▼
infra-deploy-all.yml
  ├─► infra-tier-01-environments.yml ──uses──► _infra-shared-cdktf-tier.yml  (~3 min, VPC)
  │       │ needs:
  ├─► infra-tier-02-clusters.yml      ──uses──► _infra-shared-cdktf-tier.yml  (~20 min, EKS)
  │       │ needs:
  ├─► infra-tier-03-internal-tools.yml──uses──► _infra-shared-cdktf-tier.yml  (~3 min, LBC)
  │       │ needs:
  └─► infra-tier-04-applications.yml  ──uses──► _infra-shared-cdktf-tier.yml  (~3 min, Helm)
```

`deploy-all` chains them with `needs:` so they run **strictly sequentially** — each tier reads remote state from lower tiers, so order matters. Total wall time: ~30 min from cold.

You can also run any tier individually (`gh workflow run infra-tier-XX-...yml`) or push code matching a tier's `paths:` filter — but you're responsible for ordering.

### Flow B — App release (normal cadence)

```text
git tag vX.Y.Z && gh release create vX.Y.Z --generate-notes
       │
       │ release.published event
       ▼
app-release.yml
  ├─► resolve-tag                     extracts vX.Y.Z (~3 s)
  │       │ needs:
  ├─► build ──uses──► app-build.yml
  │       │              ├─ nix build .#rust-demo-image (Cachix-backed)
  │       │              └─ docker tag + push to ECR (vX.Y.Z + latest)
  │       │ needs:
  ├─► deploy ──uses──► infra-tier-04-applications.yml ──uses──► _infra-shared-cdktf-tier.yml
  │       │              └─ cdktf deploy devnet --var=image_tag=vX.Y.Z
  │       │                 (Helm release rolls; LBC updates targets)
  │       │ needs:
  └─► smoke-test                      kubectl + curl /version, asserts vX.Y.Z is live
```

Total wall time: ~5–8 min on a warm Cachix cache. Tiers 01/02/03 are not touched.

### What auto-fires from a `git push`?

Per-tier workflows have `push: branches: [main], paths: [<tier-dir>/**]` so changing infra code redeploys *only* that tier. Changing `app/`-only files triggers nothing — those go through the release flow. `infra-deploy-all.yml` and `app-release.yml` never auto-fire from push.

### Mental model

- **`_infra-shared-cdktf-tier.yml`** is the engine. It knows how to run `cdktf` safely (auth via OIDC, install Terraform, derive the state-backend names, hold the per-env concurrency lock, log to artifacts).
- The **four `tier-XX-...yml`** files are 30-line wrappers that say *"my code is here, please plan+apply stack `devnet`."* They exist so each tier can have its own triggers + path filter.
- **`app-build.yml`** is the sibling engine for the Nix → ECR side of the world.
- **`infra-deploy-all.yml`** is the manual *"spin up everything"* button.
- **`app-release.yml`** is the automated *"ship a new app version"* pipe.

### One subtle gotcha — `release.published` reads its workflow YAML from the *tag's* commit

When `gh release create vX.Y.Z` fires `app-release.yml`, the workflow file used is the one in the repo at the **tag's ref**, not at `main` HEAD. So if you push a fix to the workflow YAML, then tag at an older commit, the fix won't take effect for that release. Always tag at HEAD (or after the workflow fix is merged) — or move the tag forward (`git tag -f` + `git push -f origin <tag>`) if you need to re-release.

</details>

<details>
<summary><b>Architecture overview</b></summary>

```text
   ┌──────────────────────────────────────────────────────────┐
   │              GitHub Actions (OIDC, no secrets)           │
   │  deploy-all → tier-01 → tier-02 → tier-03 → tier-04      │
   │  app-release (on tag) → app-build → tier-04 → smoke-test │
   └────────────────────────┬─────────────────────────────────┘
                            │ assume role cdktf-demo-gha
                            ▼
   ┌──────────────────────────────────────────────────────────┐
   │ AWS account (profile: radupopa, region: eu-central-1)    │
   │                                                          │
   │  Tier 1   VPC 10.251.0.0/20, 2 public + 2 private /24,   │
   │           single NAT, S3 gw endpoint                     │
   │                                                          │
   │  Tier 2   EKS 1.30 (public endpoint, IRSA on)            │
   │           nodegroup: t3.small  (workload=rust-demo)      │
   │           ECR repo: cdktf-demo/rust-demo                 │
   │           Secrets Manager skeletons via null_resource    │
   │                                                          │
   │  Tier 3   AWS Load Balancer Controller (Helm + IRSA)     │
   │           cert-manager (off by default)                  │
   │                                                          │
   │  Tier 4   Helm release of app/helm/rust-demo             │
   │           Ingress → ALB (via LBC), /version + /health    │
   └──────────────────────────────────────────────────────────┘

  Build pipeline:
     local nix build  ─push─►  Cachix radupopa2010  ◄─pull─  CI nix build
     CI nix build      ─push─►  Cachix radupopa2010  ◄─pull─  local nix run
```

</details>

<details>
<summary><b>Prereqs</b></summary>

- AWS account, `aws configure sso` profile **radupopa** with admin-ish access
- `nix` (with flakes enabled) — recommend [Determinate Nix](https://determinate.systems/nix/) which includes flakes + a native Linux builder for macOS
- `direnv` (optional but recommended): `brew install direnv`
- `docker` (Docker Desktop or Colima) — used by `dev-pull.sh` for local container validation
- A GitHub repo to host this (e.g. `radupopa2010/cdktf-demo`)
- The `gh` CLI authenticated: `gh auth login`

Everything else (cdktf, terraform, kubectl, helm, awscli, jq, cachix) comes from the Nix devshell.

### macOS: enable the native Linux builder (optional, for cross-arch Cachix)

This lets your Mac build `x86_64-linux` artifacts locally so `cachix push` warms the cache for CI (which runs on Linux). Without it, local and CI builds are separate Nix derivations (different arch) and don't share cache.

**Determinate Nix** (3.8.4+) ships a built-in builder using macOS's Virtualization framework. Enable it in `/etc/nix/nix.custom.conf` (not `nix.conf` — Determinate overwrites that on daemon restart):

```bash
printf 'external-builders = [{"systems":["aarch64-linux","x86_64-linux"],"program":"/usr/local/bin/determinate-nixd","args":["builder"]}]\nextra-platforms = aarch64-linux x86_64-linux\nextra-experimental-features = external-builders\n' \
  | sudo tee /etc/nix/nix.custom.conf
sudo launchctl kickstart -k system/systems.determinate.nix-daemon
nix config show | grep external-builders   # should show the JSON array
```

> **Note:** The native Linux builder is a gated feature. If you see "The Native Linux Builder is not currently available", email support@determinate.systems to request access. Alternative: use [nix-darwin's `linux-builder` module](https://nixcademy.com/posts/macos-linux-builder/) (open-source, boots a lightweight NixOS VM).

Once enabled, `nix build .#packages.x86_64-linux.rust-demo-image` cross-builds the same image CI produces. Push it to Cachix and CI gets a direct cache hit.

### Running `cdktf plan` locally

Terraform 1.14+ can't resolve AWS SSO tokens the same way the AWS CLI does. Export explicit STS credentials before running cdktf:

```bash
# 1. Login (if session expired — SSO sessions last 8-12 hours)
aws sso login --profile radupopa

# 2. Export creds + state backend vars (the .envrc does this automatically with direnv)
export CDKTF_STATE_BUCKET="cdktf-demo-tfstate-$(aws sts get-caller-identity --profile radupopa --query Account --output text)"
export CDKTF_STATE_LOCK_TABLE="cdktf-demo-tfstate-lock"
eval "$(aws configure export-credentials --profile radupopa --format env)"

# 3. Plan any tier
cd tier-01-cdktf-environments && npm install && npx cdktf get && npx cdktf plan devnet
cd tier-02-cdktf-clusters      && npm install && npx cdktf get && npx cdktf plan devnet
cd tier-03-cdktf-internal-tools && npm install && npx cdktf get && npx cdktf plan devnet
cd tier-04-cdktf-applications   && npm install && npx cdktf get && npx cdktf plan devnet
```

If you use `direnv`, the `.envrc` at the repo root handles steps 2 automatically — just `direnv allow` once.

### Alternative caching strategy (not used here)

For maximum Nix cache efficiency, freeze `Cargo.toml` at `version = "0.1.0"` and inject the real version via `APP_VERSION` env var at build time. This keeps the deps derivation hash stable across releases — only the app binary recompiles (~4s instead of ~60s). Trade-off: requires `--impure` flag (breaks `nix flake check`) and is non-standard Cargo practice. See [Union Labs' crane.nix](https://github.com/unionlabs/union/blob/main/tools/rust/crane.nix) for a production example of this pattern.

</details>

<details>
<summary><b>One-time bootstrap</b></summary>

Run these once in order. Each is idempotent.

### 1. Enter the dev shell

```bash
direnv allow                         # or: nix develop
```

### 2. Create the Terraform state backend (S3 + DynamoDB)

```bash
./scripts/bootstrap-tf-backend.sh
# Note the exported CDKTF_STATE_BUCKET / CDKTF_STATE_LOCK_TABLE values.
```

### 3. Create the GitHub OIDC role in AWS

GitHub Actions authenticates to AWS by exchanging a short-lived OIDC token for STS credentials — no long-lived `AWS_ACCESS_KEY_ID` ever leaves AWS. Two AWS objects make this work:

1. An **IAM OIDC identity provider** trusting `token.actions.githubusercontent.com` (one per AWS account, reused across all repos).
2. An **IAM role** (`cdktf-demo-gha`) with a trust policy scoped to *this* repo so only workflows from `<owner>/cdktf-demo` can assume it.

The bootstrap script creates both, idempotently:

```bash
GITHUB_OWNER=radupopa2010 GITHUB_REPO=cdktf-demo \
  ./scripts/bootstrap-github-oidc.sh
```

<details>
<summary>What it does (manual equivalent, in case you want to review)</summary>

```bash
# 3a. Create the OIDC provider (one-shot per account)
aws iam create-open-id-connect-provider --profile radupopa \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# 3b. Create the role with a trust policy that ONLY accepts
#     OIDC tokens whose `sub` claim matches your repo
aws iam create-role --profile radupopa \
  --role-name cdktf-demo-gha \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals":  { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        "StringLike":    { "token.actions.githubusercontent.com:sub": "repo:radupopa2010/cdktf-demo:*" }
      }
    }]
  }'

# 3c. Attach permissions (demo: Admin; tighten for production)
aws iam attach-role-policy --profile radupopa \
  --role-name cdktf-demo-gha \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Verify:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --profile radupopa --query Account --output text)
aws iam get-role --profile radupopa --role-name cdktf-demo-gha \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition'
aws iam list-attached-role-policies --profile radupopa --role-name cdktf-demo-gha
echo "AWS_ROLE_ARN = arn:aws:iam::${ACCOUNT_ID}:role/cdktf-demo-gha"
```

The script is safe to re-run — it `update-assume-role-policy`s if the role already exists, so you can rotate the trust policy (e.g. tighten the `sub` to a specific environment) without destroying the role.

**Tightening for production**: replace the `sub` glob `repo:owner/repo:*` with one of:

- `repo:owner/repo:ref:refs/heads/main` (only main branch)
- `repo:owner/repo:environment:production` (only when GitHub environment `production` is the target)
- `repo:owner/repo:pull_request` (only PR contexts)

</details>

### 4. Configure GitHub repo (no secrets — only repo variables)

In **Settings → Secrets and variables → Actions → Variables**:

| Variable | Value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::<account>:role/cdktf-demo-gha` (from previous step) |
| `AWS_REGION` | `eu-central-1` |
| `CACHIX_CACHE_NAME` | `radupopa2010` |

Do **not** add anything to the **Secrets** tab. Real secrets live in AWS Secrets Manager.

### 5. Refresh the LBC IAM policy

```bash
./scripts/refresh-lbc-policy.sh
```

### 6. Deploy + populate secrets

The remaining setup (deploy each tier in order, put the Cachix token in AWS Secrets Manager, cut the first release) is the script-able part of the demo. Follow [`docs/demo.md`](./docs/demo.md) → "Tonight" section.

</details>

<details>
<summary><b>Day-to-day</b></summary>

### Trigger a full deploy from CI

```bash
gh workflow run infra-deploy-all.yml -f confirm=devnet
gh run watch
```

### Trigger one tier

```bash
gh workflow run infra-tier-02-clusters.yml
```

### Cut a release of the app

```bash
git tag -a v0.1.1 -m "bump to 0.1.1"
git push origin v0.1.1
gh release create v0.1.1 --generate-notes
# app-release.yml auto-fires: nix build → push to ECR → tier-04 deploys with new tag → smoke-test
```

### Verify the running app

```bash
ALB=$(kubectl get ing rust-demo -n rust-demo \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$ALB/version"   # → {"version":"0.1.1","commit":"<sha>"}
./scripts/smoke-test.sh v0.1.1
```

</details>

<details>
<summary><b>Local ↔ cloud parity (the validation flow)</b></summary>

The story Nix + Cachix tells in this demo is **the artifact you run on your laptop is the artifact CI ships to ECR**. Three scripts cover the three meaningful checks:

| Script | What it proves | Works on |
|---|---|---|
| `./scripts/dev-up.sh` | Source compiles; new version actually serves; Cachix used | Anywhere (default mode runs the native binary via `nix run`) |
| `./scripts/dev-up.sh --container` | Same, but inside the OCI image Nix produces | Linux hosts; macOS only with [nix-darwin's linux-builder](https://nixcademy.com/posts/macos-linux-builder/) |
| `./scripts/dev-pull.sh v0.1.X` | The **exact bits** CI pushed to ECR run on your laptop | Anywhere (Rosetta on Apple Silicon) |
| `./scripts/smoke-test.sh v0.1.X` | The deployed ALB is serving that version | Anywhere with kubectl access to the cluster |
| `./scripts/dev-build-multi.sh` | Image builds for both linux/amd64 + linux/arm64 from one host | Linux native; macOS only with linux-builder |

Tear down whatever `dev-up.sh` started with `./scripts/dev-down.sh`.

### Apple Silicon caveat

`dockerTools.buildLayeredImage` builds for the host architecture. On an M-series Mac that means an arm64 image (or a Mach-O binary if you use the native mode — which is fine because we run it directly, not in Docker). For the OCI flow, either set up nix-darwin's linux-builder (one-time) or use `dev-pull.sh` to fetch from ECR.

### Nix + Cachix without containers

```bash
# As a reader — pull from cache, no compile
cachix use radupopa2010
nix run .#rust-demo

# As a contributor — push your build to the cache
cachix authtoken <your-personal-token>
nix build .#rust-demo
nix build .#rust-demo --print-out-paths | cachix push radupopa2010
# Next CI run reuses these store paths.
```

</details>

<details>
<summary><b>Tear down</b></summary>

```bash
./scripts/destroy-all.sh
# Reverse tier order: tier-04 → tier-03 → tier-02 → tier-01.
# Safe to re-run; failures don't cascade (set +e per tier).
```

</details>

<details>
<summary><b>What's intentionally NOT in this demo</b></summary>

- **No Route 53 / TLS**: ALB serves plain HTTP on its own DNS name. Add cert-manager + a Route 53 zone for prod.
- **No multi-AZ NAT**: one NAT gateway to keep costs near zero. Toggle in `tier-01/modules/aws-network/main.tf`.
- **No observability tier**: no Prometheus, Grafana, Loki, Tempo. Add as `tier-05-cdktf-observability` following the same skill+module+stack pattern.
- **No environment promotion (testnet/mainnet)**: every `environments.jsonc` keeps the structure but comments out non-devnet sections. Onboard a new env by uncommenting + adding a stack instantiation in the tier's `main.ts`.
- **`AdministratorAccess` on the GHA role**: too broad for prod. Tighten via `bootstrap-github-oidc.sh` to the minimum set: `AmazonVPCFullAccess`, `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryFullAccess`, `IAMFullAccess` (for IRSA), `SecretsManagerReadWrite`, plus scoped `s3:*` + `dynamodb:*` on the TF-state bucket and lock table.

</details>

<details>
<summary><b>Useful entry points for future you (or AI)</b></summary>

- Demo runbook: [`docs/demo.md`](./docs/demo.md)
- AI guidelines: [`CLAUDE.md`](./CLAUDE.md)
- Per-tier skills: `.claude/skills/tier-XX-*/SKILL.md`
- Safe `cdktf` invocation: `.claude/skills/cdktf/SKILL.md`
- Workflow triggering: `.claude/skills/github-workflow-trigger/SKILL.md`

</details>
