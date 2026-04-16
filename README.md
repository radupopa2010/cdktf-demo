# cdktf-demo

A small but realistic demo of the multi-tier CDKTF pattern from Movement Labs, scaled down to one environment (`devnet`), one AWS region (`eu-central-1`), and one tiny Rust app on EKS. Built with Nix + Cachix for reproducible local & CI builds, deployed via GitHub Actions using OIDC + AWS Secrets Manager (no GitHub-stored secrets).

See [`plan.md`](./plan.md) for the full design and [`tasks.md`](./tasks.md) for live build progress.

## What's in here

```text
.
├── tier-01-cdktf-environments/      # VPC + subnets + NAT (calls terraform-aws-modules/vpc/aws)
├── tier-02-cdktf-clusters/          # EKS + dedicated nodegroup + ECR + Secrets Manager skeleton
├── tier-03-cdktf-internal-tools/    # AWS Load Balancer Controller (+ optional cert-manager)
├── tier-04-cdktf-applications/      # Helm release of the rust-demo app
├── app/                             # Rust + axum demo service, Helm chart, docker-compose
├── flake.nix                        # Reproducible Rust toolchain + OCI image, Cachix-cached
├── .github/workflows/               # One workflow per tier + orchestrator + app-release
├── scripts/                         # Bootstrap + deploy-all + destroy-all helpers
├── minikube/                        # Laptop-local k8s flow (no AWS)
└── .claude/skills/                  # Per-tier AI skills + cdktf safety + workflow trigger
```

## Architecture overview

```text
   ┌──────────────────────────────────────────────────────────┐
   │              GitHub Actions (OIDC, no secrets)           │
   │  deploy-all → tier-01 → tier-02 → tier-03 → tier-04      │
   │              app-release (on tag) → app-build → tier-04  │
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

## Prereqs

- AWS account, `aws configure sso` profile **radupopa** with admin-ish access
- `nix` (with flakes enabled): `bash <(curl -L https://nixos.org/nix/install)` then `mkdir -p ~/.config/nix && echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf`
- `direnv` (optional but recommended): `brew install direnv`
- A GitHub repo to host this (let's say `<owner>/cdktf-demo`)
- The `gh` CLI authenticated: `gh auth login`

Everything else (cdktf, terraform, kubectl, helm, awscli, jq, cachix) comes from the Nix devshell.

## One-time bootstrap

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

What it does (and what you'd run by hand if you didn't use the script):

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

**Verify:**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --profile radupopa --query Account --output text)
aws iam get-role --profile radupopa --role-name cdktf-demo-gha \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition'
# Should print the StringLike condition with your repo.

aws iam list-attached-role-policies --profile radupopa --role-name cdktf-demo-gha
# Should list AdministratorAccess.

echo "AWS_ROLE_ARN = arn:aws:iam::${ACCOUNT_ID}:role/cdktf-demo-gha"
```

The script is safe to re-run — it `update-assume-role-policy`s if the role already exists, so you can rotate the trust policy (e.g. tighten the `sub` to a specific environment) without destroying the role.

**Tightening for production**: replace the `sub` glob `repo:owner/repo:*` with one of:

- `repo:owner/repo:ref:refs/heads/main` (only main branch)
- `repo:owner/repo:environment:production` (only when GitHub environment `production` is the target)
- `repo:owner/repo:pull_request` (only PR contexts)

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

### 6. Deploy tier-02 once (so secret shells exist)

You can do this from CI — `gh workflow run tier-02-clusters.yml` — or locally for the first time. After tier-02 has run, the `null_resource` modules have created the secret SHELLS in AWS Secrets Manager.

### 7. Populate the secret values

```bash
./scripts/bootstrap-secrets.sh
# You'll be prompted for the Cachix push token (cache: radupopa2010).
# Get one at https://app.cachix.org/personal-auth-tokens
```

The token is `aws secretsmanager put-secret-value`'d into `cdktf-demo/devnet/cachix-radupopa2010-token`. Tier-02's terraform never sees the value.

## First deployment walkthrough (the demo flow)

End-to-end first run, in the order it should happen. Each step states an expected duration and how to know it succeeded. The whole walkthrough takes ~40 minutes wall-clock, mostly waiting on EKS.

### A. Push the code to GitHub

```bash
git init -b main
git add .
git commit -m "initial cdktf-demo scaffold"
git remote add origin git@github.com:radupopa2010/cdktf-demo.git
git push -u origin main
```

> The push will trigger every `tier-*.yml` workflow at once because all four tier paths just changed. Three of them (tier-02/03/04) will fail on this very first push because the lower tiers haven't deployed yet — that's expected. We'll re-run them in order in the next steps. Once the demo is past the first deploy, the path filters do the right thing on subsequent pushes.

### B. Deploy tier-01 (VPC) — ~3 minutes

```bash
gh workflow run tier-01-environments.yml
gh run watch
```

Success when: the run is green and the workflow's "cdktf deploy" step shows `Apply complete! Resources: ~24 added`.

### C. Deploy tier-02 (EKS + ECR + secret shells) — ~20 minutes

```bash
gh workflow run tier-02-clusters.yml
gh run watch
```

Success when: green. EKS control plane is the slow part (~12 min) followed by node group rollout (~5 min). At the end, the secret SHELL `cdktf-demo/devnet/cachix-radupopa2010-token` exists in AWS Secrets Manager (no value yet).

Verify from your laptop:

```bash
aws secretsmanager describe-secret --profile radupopa \
  --secret-id cdktf-demo/devnet/cachix-radupopa2010-token
aws eks update-kubeconfig --profile radupopa --region eu-central-1 --name cdktf-demo-devnet
kubectl get nodes   # should show 1 t3.small node, Ready
```

### D. Put the Cachix push token in Secrets Manager

```bash
./scripts/bootstrap-secrets.sh
# Paste the token from https://app.cachix.org/personal-auth-tokens
# (cache: radupopa2010, scope: write).
```

This is the **only** time you ever interactively type a secret value. From here on, CI loads it via `aws secretsmanager get-secret-value` after the OIDC step.

### E. Deploy tier-03 (AWS Load Balancer Controller) — ~3 minutes

```bash
./scripts/refresh-lbc-policy.sh    # one-shot: fetch upstream IAM policy
git add tier-03-cdktf-internal-tools/modules/kubernetes-aws-load-balancer-controller/iam-policy.json
git commit -m "tier-03: refresh LBC IAM policy"
git push
gh workflow run tier-03-internal-tools.yml
gh run watch
```

Success when: `kubectl get pods -n kube-system | grep aws-load-balancer-controller` shows 2 pods running.

### F. Open a PR with a small app change (the "PR demo" beat)

```bash
git checkout -b bump-greeting
# Tiny edit — e.g. change the /version response message in app/src/main.rs
git commit -am "app: include build commit in /version response"
git push -u origin bump-greeting
gh pr create --fill
```

The push triggers the per-tier workflows that touch changed paths — for an app-only change, none of them fire (the tier dirs are untouched). Add a tier change to demo per-tier triggers if you want to see them light up.

```bash
gh pr merge --squash --delete-branch
```

### G. Cut the first release — `app-release.yml` does everything

```bash
git checkout main && git pull
git tag -a v0.1.0 -m "first cdktf-demo release"
git push origin v0.1.0
gh release create v0.1.0 --generate-notes
gh run watch
```

What runs automatically:

1. `app-release.yml` resolves the tag → `image_tag=v0.1.0`.
2. `app-build.yml` (reusable) — Nix builds `rust-demo-image`, Cachix push (token from AWS SM), `docker tag` + `docker push` to ECR with both `v0.1.0` and `latest`.
3. `tier-04-applications.yml` — `cdktf deploy devnet -var image_tag=v0.1.0`. Helm release renders, AWS Load Balancer Controller provisions an ALB.

ALB takes ~3 minutes to become healthy after the Helm release lands.

### H. Hit the endpoint

```bash
ALB=$(kubectl get ing rust-demo -n rust-demo \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$ALB"
curl "http://$ALB/version"
# → {"version":"0.1.0","commit":"<git-sha>"}
curl -I "http://$ALB/health"
# → HTTP/1.1 200 OK
```

### I. The closer — bump and re-release to show the rolling update

```bash
# In app/Cargo.toml: version = "0.1.1"
cd app && cargo update --workspace --offline 2>/dev/null; cd ..
git commit -am "app: bump to 0.1.1"
git push
git tag -a v0.1.1 -m "0.1.1: nothing changed but the version, that's the point"
git push origin v0.1.1
gh release create v0.1.1 --generate-notes
gh run watch
```

Watch the rolling deploy:

```bash
kubectl -n rust-demo rollout status deploy/rust-demo
curl "http://$ALB/version"
# → {"version":"0.1.1","commit":"<new-sha>"}
```

The Cachix payoff: the second build reuses the cached Rust artifacts from the first, so step G's ~6 min compile is now ~30 s.

### Demo cheat-sheet (one terminal, one window)

```bash
# Setup (assumes bootstrap already done)
gh workflow run tier-01-environments.yml && gh run watch
gh workflow run tier-02-clusters.yml      && gh run watch
./scripts/bootstrap-secrets.sh
gh workflow run tier-03-internal-tools.yml && gh run watch

# The actual demo beats
git tag -a v0.1.0 -m "first" && git push origin v0.1.0
gh release create v0.1.0 --generate-notes && gh run watch
ALB=$(kubectl get ing rust-demo -n rust-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$ALB/version"

# Bump → second release → rolling update
sed -i '' 's/^version = "0.1.0"/version = "0.1.1"/' app/Cargo.toml
git commit -am "app: 0.1.1"
git tag -a v0.1.1 -m "second" && git push origin v0.1.1 origin
gh release create v0.1.1 --generate-notes && gh run watch
curl "http://$ALB/version"
```

## Day-to-day

### Trigger a full deploy from CI

```bash
gh workflow run deploy-all.yml -f confirm=devnet
gh run watch
```

### Trigger one tier

```bash
gh workflow run tier-02-clusters.yml
```

### Cut a release of the app (recommended deploy path)

```bash
git tag -a v0.1.1 -m "bump to 0.1.1"
git push origin v0.1.1
gh release create v0.1.1 --generate-notes
# app-release.yml auto-fires: nix build → push to ECR → tier-04 deploys with new tag
```

### Verify the running app

```bash
ALB=$(kubectl get ing rust-demo -n rust-demo \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$ALB/version"   # → {"version":"0.1.1","commit":"<sha>"}
curl -I "http://$ALB/health" # → 200 OK
```

## Local development

### App-only (Docker Compose, no Kubernetes)

```bash
cd app
docker compose up --build
curl localhost:8080/version
```

### Full stack on Kubernetes (Minikube)

See [`minikube/README.md`](./minikube/README.md).

### Build via Nix + Cachix (the demo)

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

## Tear down

```bash
./scripts/destroy-all.sh
# Reverse tier order: tier-04 → tier-03 → tier-02 → tier-01.
# Safe to re-run; failures don't cascade (set +e per tier).
```

## What's intentionally NOT in this demo

- **No Route 53 / TLS**: ALB serves plain HTTP on its own DNS name. Add cert-manager + a Route 53 zone for prod.
- **No multi-AZ NAT**: one NAT gateway to keep costs near zero. Toggle in `tier-01/modules/aws-network/main.tf`.
- **No observability tier**: no Prometheus, Grafana, Loki, Tempo. Add as `tier-05-cdktf-observability` following the same skill+module+stack pattern.
- **No environment promotion (testnet/mainnet)**: every `environments.jsonc` keeps the structure but comments out non-devnet sections. Onboard a new env by uncommenting + adding a stack instantiation in the tier's `main.ts`.
- **`AdministratorAccess` on the GHA role**: too broad for prod. Tighten via `bootstrap-github-oidc.sh` to the minimum set listed in `plan.md` §4b.

## Useful entry points for future you (or AI)

- Plan & rationale: [`plan.md`](./plan.md)
- Live progress: [`tasks.md`](./tasks.md)
- AI guidelines: [`CLAUDE.md`](./CLAUDE.md)
- Per-tier skills: `.claude/skills/tier-XX-*/SKILL.md`
- Safe `cdktf` invocation: `.claude/skills/cdktf/SKILL.md`
- Workflow triggering: `.claude/skills/github-workflow-trigger/SKILL.md`
