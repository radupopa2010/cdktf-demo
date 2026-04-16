# cdktf-demo — Plan

A demo project that mirrors the multi-tier CDKTF pattern used at Movement Labs, scaled down to a minimal, cheap, single-environment (devnet only) deployment of a small Rust web service on EKS. Built and deployed via GitHub Actions, with Nix + Cachix for reproducible builds and shared cache between local dev and CI. Local development supported via Docker Compose (for app devs) and Minikube (for infra folk).

> Source of truth for tiering, naming, and skill conventions:
> `/Users/radupopa/p/move/infrastructure-workspace/` (Movement Labs workspace)
> and `/Users/radupopa/p/radu/random-code/001-ai-infra/` (DDD-inspired tier pattern).

---

## 1. Decisions (locked)

| Topic | Decision | Why |
|---|---|---|
| Cloud / account | AWS, single account, `aws --profile radupopa` | Per task spec — no new accounts. |
| Region | `eu-central-1` | Closer to user; one region only to keep it cheap. |
| Environment | `devnet` only | Per task spec. |
| Repo layout | Monorepo `cdktf-demo` | Easier to follow as a demo. |
| Tiers | 4 tiers (env / cluster / internal-tools / applications) | Mirrors Movement pattern; keeps blast-radius isolation visible. |
| State backend | S3 + DynamoDB lock | Realistic for CI; bootstrap script creates them. |
| DNS | ALB DNS hostname only, no Route 53 | No domain to manage. |
| Ingress | AWS Load Balancer Controller + Kubernetes `Ingress` (ALB target type `ip`) | Same pattern as Movement (LBC manages ALB from Ingress). |
| App | Rust + `axum`, endpoints `/version` (returns semver), `/health` (ALB health check) | Lightweight, demo-friendly. |
| Build | Nix flake (`flake.nix`) | Reproducible local + CI builds. |
| Cache | Cachix cache `radupopa2010` (owner: integer-it). Public key `radupopa2010.cachix.org-1:BjufnV1F5zRtjpzEBeV2GGt/04DOrQgq2glSyJKE9ZU=` baked into `flake.nix` and CI config so reads need no token. | Demonstrates local↔CI cache reuse. |
| Container registry | Amazon ECR, created in tier-02 | One-account rule; nearby cluster. |
| AWS auth from CI | GitHub OIDC → IAM role (no long-lived keys) | Best practice; documented in README. |
| Secrets storage | AWS Secrets Manager only | Per task spec — no secrets in GitHub Actions, no secrets in tfvars. |
| Secret creation | `null_resource` + `local-exec` calling `aws secretsmanager create-secret` (idempotent: describe-or-create); values written separately by a bootstrap script so they never enter TF state | Per task spec; keeps state clean. |
| Secret consumption | `data.aws_secretsmanager_secret_version` in Terraform; `aws secretsmanager get-secret-value` in CI steps after OIDC auth | Single source of truth. |
| GitHub config | Only **variables** (not secrets): `AWS_ROLE_ARN`, `AWS_REGION`, `CACHIX_CACHE_NAME`. CI assumes the OIDC role, then pulls any real secret (e.g. `CACHIX_AUTH_TOKEN`) from Secrets Manager. | No long-lived secrets stored in GitHub. |
| Tests / lint | `npm run lint`, `npm run typecheck`, `cdktf synth` per tier | Per Movement workspace conventions. |

## 2. Repository layout

```
cdktf-demo/
├── plan.md                        ← this file
├── tasks.md                       ← live task tracker (updated as work progresses)
├── README.md                      ← how to deploy / verify / destroy
├── CLAUDE.md                      ← AI guide: tier ownership, naming, anti-patterns
├── flake.nix                      ← Rust toolchain + app build (Cachix-friendly)
├── flake.lock
├── .envrc                         ← direnv: `use flake`
├── .github/
│   └── workflows/
│       ├── tier-01-environments.yml
│       ├── tier-02-clusters.yml
│       ├── tier-03-internal-tools.yml
│       ├── tier-04-applications.yml
│       ├── deploy-all.yml         ← orchestrator (workflow_dispatch only)
│       ├── app-build.yml          ← reusable, builds + pushes Rust image via Nix
│       └── app-release.yml        ← triggered on `release: published` (or tag v*)
│
├── app/                           ← the Rust demo app
│   ├── Cargo.toml
│   ├── Cargo.lock
│   ├── src/main.rs                ← axum: /version, /health
│   ├── docker-compose.yml         ← local dev for app folk
│   └── helm/                      ← chart consumed by tier-04
│       └── rust-demo/
│
├── minikube/                      ← infra-team local dev
│   ├── README.md
│   ├── start.sh
│   └── manifests/                 ← bare manifests / kustomize for laptop runs
│
├── tier-01-cdktf-environments/
│   ├── cdktf.json
│   ├── package.json
│   ├── environments.jsonc         ← one root + one devnet section ACTIVE; rest commented
│   ├── terraform.devnet.tfvars.json
│   ├── modules/                   ← terraform HCL modules called from CDKTF
│   │   └── aws-network/           ← VPC + subnets + NAT
│   └── src/infra/
│       ├── main.ts
│       ├── stacks/
│       └── tools/                 ← config loader (jsonc-parser)
│
├── tier-02-cdktf-clusters/
│   ├── cdktf.json
│   ├── package.json
│   ├── environments.jsonc
│   ├── terraform.devnet.tfvars.json
│   ├── modules/
│   │   ├── aws-eks-cluster/       ← EKS control plane
│   │   ├── aws-eks-nodegroup/     ← dedicated node pool for the app
│   │   └── aws-ecr/               ← ECR repo for the Rust image
│   └── src/infra/...
│
├── tier-03-cdktf-internal-tools/
│   ├── cdktf.json
│   ├── package.json
│   ├── environments.jsonc
│   ├── terraform.devnet.tfvars.json
│   ├── modules/
│   │   ├── kubernetes-aws-load-balancer-controller/
│   │   └── kubernetes-cert-manager/   ← optional, scaffolded for completeness
│   └── src/infra/...
│
├── tier-04-cdktf-applications/
│   ├── cdktf.json
│   ├── package.json
│   ├── environments.jsonc
│   ├── terraform.devnet.tfvars.json
│   ├── modules/
│   │   └── kubernetes-rust-demo/  ← Helm release of app/helm/rust-demo
│   └── src/infra/...
│
├── scripts/
│   ├── bootstrap-tf-backend.sh    ← creates S3 bucket + DynamoDB table once
│   ├── deploy-all.sh              ← local equivalent of orchestrator workflow
│   ├── destroy-all.sh             ← reverse order, set +e
│   └── set-aws-profile.sh         ← exports AWS_PROFILE=radupopa
│
└── .claude/
    └── skills/
        ├── cdktf/SKILL.md                ← safe `cdktf` invocation; pipes output to log file
        ├── tier-01-environments/SKILL.md
        ├── tier-02-clusters/SKILL.md
        ├── tier-03-internal-tools/SKILL.md
        ├── tier-04-applications/SKILL.md
        ├── github-workflow-trigger/SKILL.md   ← how to dispatch / wait on workflows
        └── rust-app/SKILL.md
```

## 3. Tier breakdown

### Tier 01 — `tier-01-cdktf-environments`

- **Owns:** VPC, public + private subnets across 2 AZs (ALB needs ≥ 2), Internet Gateway, single NAT Gateway (cheap), default route tables, S3 VPC gateway endpoint.
- **Module style:** CDKTF stack calls a local Terraform HCL module under `modules/aws-network/` (per task: "use terraform modules called from cdktf files"). Also calls `terraform-aws-modules/vpc/aws` from registry as a reference pattern.
- **Outputs:** `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `region`.
- **environments.jsonc:** one root section + one devnet section enabled; everything else (testnet, mainnet, etc.) commented out, not removed (per task spec).
- **Smallest config:** /20 VPC, /24 subnets, single NAT (not one-per-AZ) to keep cost down.

### Tier 02 — `tier-02-cdktf-clusters`

- **Owns:** EKS cluster (Kubernetes 1.30, public endpoint with restricted CIDR), one **dedicated** managed node group for the app (`t3.small`, min=1 max=2 desired=1), IAM role for service accounts (IRSA) OIDC provider, ECR repo `cdktf-demo/rust-demo`.
- **Reads from tier-01:** VPC + subnets via `terraform_remote_state`.
- **Modules called:** local HCL modules `aws-eks-cluster`, `aws-eks-nodegroup`, `aws-ecr` + community `terraform-aws-modules/eks/aws` as the heavy lifter.
- **Outputs:** `cluster_name`, `cluster_endpoint`, `cluster_ca`, `oidc_provider_arn`, `node_role_arn`, `ecr_repo_url`.
- **Cheap knobs:** single AZ for nodes, no logging exports, default add-ons only.

### Tier 03 — `tier-03-cdktf-internal-tools`

- **Owns:** AWS Load Balancer Controller (Helm chart) with IRSA, cert-manager (scaffolded but optional).
- **Reads from tier-02:** cluster endpoint, OIDC provider ARN.
- **Why a separate tier:** matches Movement Labs `cdktf-internal-tools` pattern; keeps app tier free of cluster-platform concerns.

### Tier 04 — `tier-04-cdktf-applications`

- **Owns:** Helm release of `app/helm/rust-demo`, Kubernetes `Ingress` annotated for ALB (LBC provisions the ALB).
- **Reads from tier-02:** cluster endpoint + ECR URL.
- **Image tag:** parameterised; default = `latest`, overridden by app-release workflow with the git tag (semver).

## 4. Rust app

- **Crate:** `rust-demo`, axum 0.7, single binary.
- **Endpoints:**
  - `GET /version` → `{"version": "0.1.0", "commit": "abc1234"}` (semver from `CARGO_PKG_VERSION`, commit injected at build via env var).
  - `GET /health` → `200 OK` for ALB.
- **Build:** Nix flake using `crane` or `naersk` for Rust → Cachix-friendly.
- **Container image:** built by Nix (`pkgs.dockerTools.buildImage`) so the same flake produces the dev shell, the binary, and the OCI image.
- **Local dev (app folk):** `docker compose up` runs the app on `:8080`.
- **Local dev (infra folk):** `minikube/start.sh` boots minikube and applies tier-04 manifests against it.

## 4a. Secrets management

**Rule:** all secrets live in AWS Secrets Manager (devnet only). No secrets in GitHub Actions, no secrets in `tfvars`, no secrets in code.

### Inventory (devnet)

| Secret name | Used by | Created by |
|---|---|---|
| `cdktf-demo/devnet/cachix-radupopa2010-token` | CI step that pushes Nix store paths to Cachix; optional for local devs (read-only is anonymous) | bootstrap script (one-shot) |
| `cdktf-demo/devnet/github-pat-trigger` | (optional) only if we want one tier workflow to dispatch another via REST instead of `workflow_call` | bootstrap script |

If we add an observability tier later (Grafana admin, etc.), each new secret follows the same pattern.

### Creation pattern (Terraform-side)

```hcl
# tier-02-cdktf-clusters/modules/aws-secrets/main.tf
resource "null_resource" "ensure_secret" {
  for_each = toset(var.secret_names)

  triggers = { name = each.value }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      aws --profile "${var.aws_profile}" --region "${var.region}" \
        secretsmanager describe-secret --secret-id "${each.value}" \
        > /dev/null 2>&1 \
      || aws --profile "${var.aws_profile}" --region "${var.region}" \
           secretsmanager create-secret \
             --name "${each.value}" \
             --description "Managed by cdktf-demo" \
             --tags Key=Project,Value=cdktf-demo Key=Env,Value=devnet
    EOT
  }
}
```

The **value** is set out-of-band (CLI bootstrap script or manual `aws secretsmanager put-secret-value`) so it never lands in Terraform state.

### Consumption pattern

```hcl
data "aws_secretsmanager_secret_version" "cachix" {
  secret_id = "cdktf-demo/devnet/cachix-radupopa2010-token"
}

# Pass into a Helm release, or expose to a Pod via External Secrets Operator
```

In CI workflows:

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN }}
    aws-region: ${{ vars.AWS_REGION }}
- name: Load Cachix token from AWS
  run: |
    echo "CACHIX_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
      --secret-id cdktf-demo/devnet/cachix-radupopa2010-token \
      --query SecretString --output text)" >> "$GITHUB_ENV"
```

### Bootstrap script

`scripts/bootstrap-secrets.sh` reads values from the operator's local environment (or prompts) and runs `aws secretsmanager put-secret-value` for each. Run once after the IAM/OIDC bootstrap.

## 4b. GitHub Actions access (no secrets, OIDC-only)

This is the only manual setup the operator does. Documented in `README.md` and `scripts/bootstrap-github-oidc.sh`.

1. **Create the OIDC provider in AWS** (one-shot, idempotent):

   ```bash
   aws --profile radupopa iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create the IAM role `cdktf-demo-gha`** with trust policy scoped to your GitHub repo:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals":  { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
         "StringLike":    { "token.actions.githubusercontent.com:sub": "repo:<GH_OWNER>/cdktf-demo:*" }
       }
     }]
   }
   ```

   Attach a policy granting:
   - `AdministratorAccess` for the demo (tighten later), **or**
   - the minimal set: `AmazonVPCFullAccess`, `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryFullAccess`, `IAMFullAccess` (for IRSA), `SecretsManagerReadWrite`, `s3:*` + `dynamodb:*` on the TF-state resources.

3. **Configure the GitHub repo** (no secrets, only variables):
   - Repo → Settings → Secrets and variables → Actions → **Variables** tab → New repository variable:
     - `AWS_ROLE_ARN` = `arn:aws:iam::<ACCOUNT_ID>:role/cdktf-demo-gha`
     - `AWS_REGION` = `eu-central-1`
     - `CACHIX_CACHE_NAME` = `radupopa2010`
   - **Permissions** for the workflow are set in YAML:
     ```yaml
     permissions:
       id-token: write   # required for OIDC
       contents: read
     ```

4. **Trigger workflows from your laptop** (`gh` CLI; no AWS creds needed for the trigger itself):

   ```bash
   gh auth login
   gh workflow run deploy-all.yml -f environment=devnet
   gh run watch
   ```

5. **(Optional) Branch protection** so tier workflows require a passing `cdktf plan` before merge.

## 5. Nix + Cachix story

- `flake.nix` exposes:
  - `devShells.default` — Rust toolchain + cdktf + node + awscli + kubectl + helm + jq.
  - `packages.rust-demo` — the binary.
  - `packages.rust-demo-image` — OCI image via `dockerTools`.
- **Cachix wiring:**
  - GitHub Action: `cachix/install-nix-action` + `cachix/cachix-action@v15` with `name: ${{ vars.CACHIX_CACHE_NAME }}`. The `authToken` is loaded **from AWS Secrets Manager** in a previous step (`CACHIX_AUTH_TOKEN` env var sourced from secret `cdktf-demo/devnet/cachix-radupopa2010-token`), not from a GitHub secret.
  - Local: README explains `cachix use radupopa2010` so `nix build` pulls from the same cache, *and* `cachix push radupopa2010 result` to feed CI (the dev's local `~/.config/cachix/cachix.dhall` holds their personal token; never committed).
  - Demo flow documented:
    1. Dev builds locally → pushes to Cachix → CI reuses cache → fast CI.
    2. CI builds on tag → pushes to Cachix → dev pulls binary without rebuilding → `nix run .#rust-demo` runs the exact CI artifact.

## 6. GitHub Actions

All workflows assume AWS access via OIDC role `${{ vars.AWS_ROLE_ARN }}` (set up per §4b). No GitHub secrets are required — every secret value (Cachix token, etc.) is fetched from AWS Secrets Manager *after* the OIDC step. All workflows use the Nix devShell for tooling (no per-step installs).

| Workflow | Trigger | Purpose |
|---|---|---|
| `tier-01-environments.yml` | `workflow_dispatch`, `push` to `main` touching `tier-01-cdktf-environments/**` | `cdktf deploy devnet` for tier 01 |
| `tier-02-clusters.yml` | `workflow_dispatch`, `push` to `main` touching `tier-02-*/**` | tier 02 deploy |
| `tier-03-internal-tools.yml` | same pattern | tier 03 deploy |
| `tier-04-applications.yml` | `workflow_dispatch`, `repository_dispatch` from app-release | tier 04 deploy with image tag input |
| `deploy-all.yml` | `workflow_dispatch` only | Orchestrator: calls tiers 01→04 sequentially via reusable workflow `workflow_call` |
| `app-build.yml` | reusable (`workflow_call`) | Build app via Nix, push image to ECR, output digest |
| `app-release.yml` | `release: published` *or* `push: tags: 'v*'` | Calls `app-build`, then triggers `tier-04-applications` with the new tag |

**Plan / Apply gate:** every tier workflow runs `cdktf plan` first, uploads the plan as artifact, then `cdktf deploy --auto-approve` only on the apply job (which can require manual approval via GitHub Environments later).

## 7. Skills

Each skill follows the `001-ai-infra/.claude/skills/` pattern (frontmatter + body). They're scoped so AI agents working on one tier don't load context for the others.

- **`cdktf/SKILL.md`** — Safe `cdktf` invocation. Always `cd` into the tier dir, run `cdktf <cmd> devnet 2>&1 | tee logs/cdktf-<tier>-<cmd>-<ts>.log`. Logs are kept under `<tier>/logs/` and **gitignored**. Includes the "never interrupt cdktf" rule, the process check, and the timeout guidance.
- **`tier-01-environments/SKILL.md`** — VPC/subnet patterns, CIDR allocation logic from `environments.jsonc`, how to add a region.
- **`tier-02-clusters/SKILL.md`** — EKS knobs (version, addons, nodegroup sizing), ECR usage, IRSA setup.
- **`tier-03-internal-tools/SKILL.md`** — AWS LBC install gotchas, IAM policy JSON link, cert-manager.
- **`tier-04-applications/SKILL.md`** — Helm chart structure, image tag override, Ingress annotations for ALB.
- **`github-workflow-trigger/SKILL.md`** — how to call `gh workflow run`, list runs, fetch logs, with examples for tier dispatch and the orchestrator.
- **`rust-app/SKILL.md`** — `nix build`, `nix develop`, axum endpoint conventions, semver bumping.

## 8. Open assumptions (call out before I diverge)

1. AWS account already has the IAM permissions to create VPC/EKS/ECR; if not, I'll add a one-shot `bootstrap-iam.sh`.
2. GitHub OIDC role `cdktf-demo-gha` will be created **manually** the first time (chicken-and-egg); the README documents the trust policy, and one of the bootstrap scripts can create it on request.
3. EKS public endpoint is restricted to the user's current public IP for demo simplicity. Listed as a `TODO: tighten or move to private + bastion in production`.
4. No PagerDuty / SSO / observability tier — out of scope for the demo, called out in README.
5. The "cachix push from CI back to local" flow assumes the user has push rights on the cache (CACHIX_AUTH_TOKEN locally for write, anonymous for read).

## 9. Execution order (what I'll actually build)

Detailed and live-tracked in `tasks.md`. High level:

1. Skeleton + plan/tasks files (this commit).
2. Skills under `.claude/skills/` (so future iterations get the right context).
3. Rust app + flake.nix + Cachix wiring + docker-compose.
4. tier-01 (env/VPC) — full HCL module + CDKTF stack + envs.jsonc.
5. tier-02 (cluster/ECR).
6. tier-03 (LBC/cert-manager).
7. tier-04 (Helm release of app).
8. GitHub workflows (tier workflows → orchestrator → app-release).
9. Bootstrap scripts (TF backend, OIDC role guidance).
10. README + minikube setup.
11. Architecture validation (`cdktf synth`, `terraform validate`, `npm run lint`/`typecheck` per tier).

No real `cdktf deploy` will run from this conversation — that requires AWS creds and is the user's call. Everything is wired so a single `gh workflow run deploy-all.yml -f environment=devnet` deploys end to end once the OIDC role exists.
