# cdktf-demo — Tasks

Live tracker. Updated as work progresses. See `plan.md` for the design.

Legend: `[ ]` pending · `[~]` in progress · `[x]` done · `[!]` blocked

## 0. Planning

- [x] Clarify scope with user (region, DNS, state backend, Cachix, repo layout, Rust framework, tier scope)
- [x] Capture secrets-via-Secrets-Manager + GitHub-OIDC-no-secrets rule
- [x] Lock in real Cachix cache name `radupopa2010` + public key
- [x] Write `plan.md`
- [x] Write `tasks.md` (this file)

## 1. Skeleton & meta

- [x] Create top-level dirs (4 tiers, app, scripts, minikube, .claude/skills, .github/workflows)
- [x] Root `.gitignore`
- [x] Root `CLAUDE.md`
- [x] Root `README.md`
- [x] Root `.envrc`
- [x] Root `.markdownlint.json` + `.cspell.json`

## 2. Skills

- [x] `.claude/skills/cdktf/SKILL.md` — safe invocation, log-to-file pattern
- [x] `.claude/skills/tier-01-environments/SKILL.md`
- [x] `.claude/skills/tier-02-clusters/SKILL.md`
- [x] `.claude/skills/tier-03-internal-tools/SKILL.md`
- [x] `.claude/skills/tier-04-applications/SKILL.md`
- [x] `.claude/skills/github-workflow-trigger/SKILL.md`
- [x] `.claude/skills/rust-app/SKILL.md`
- [x] Global `~/.claude/skills/markdown-writer/SKILL.md` — markdownlint conventions for any future .md file

## 3. Rust app

- [x] `app/Cargo.toml`
- [x] `app/src/main.rs` (axum: GET /version, GET /health, GIT_COMMIT injected)
- [ ] `app/Cargo.lock` (generated on first `nix build` — needs to run once)
- [x] `app/docker-compose.yml`
- [x] `app/helm/rust-demo/` (Chart.yaml, values.yaml, templates/_helpers.tpl, deployment, service, ingress)

## 4. Nix + Cachix

- [x] Root `flake.nix` (devShell + `packages.rust-demo` via crane + `packages.rust-demo-image` via dockerTools)
- [x] Cachix public key for `radupopa2010` baked into `flake.nix` `nixConfig` (no token needed for reads)
- [ ] `flake.lock` (generated on first `nix flake update`)
- [x] CI Cachix wiring in `app-build.yml` — token fetched from AWS Secrets Manager

## 5. tier-01-cdktf-environments

- [x] `cdktf.json`, `package.json`, `tsconfig*.json`
- [x] `environments.jsonc` — devnet ACTIVE, others commented
- [x] `terraform.devnet.tfvars.json`
- [x] `modules/aws-network/{main,variables,outputs}.tf` — VPC, 2× public + 2× private /24, single NAT
- [x] `src/infra/main.ts` + `EnvironmentsDevnetStack`
- [x] `src/infra/tools/config.ts` (jsonc loader + CIDR helpers)
- [x] Outputs: vpc_id, public/private subnet ids, azs, region

## 6. tier-02-cdktf-clusters

- [x] `cdktf.json`, `package.json`, `tsconfig*.json`, `environments.jsonc`, `terraform.devnet.tfvars.json`
- [x] `modules/aws-eks-cluster/` — calls `terraform-aws-modules/eks/aws`, IRSA on
- [x] `modules/aws-eks-nodegroup/` — single t3.small group with labels/taints, bundles its IAM role
- [x] `modules/aws-ecr/` — repo `cdktf-demo/rust-demo` + scan-on-push + lifecycle policy
- [x] `modules/aws-secrets/` — `null_resource` + AWS CLI describe-or-create (idempotent), VALUE set out-of-band
- [x] `src/infra/main.ts` + `ClustersDevnetStack` reads tier-01 remote state
- [x] Outputs: cluster_name, endpoint, ca, oidc_provider_arn, oidc_issuer_url, node_role_arn, ecr_repo_url

## 7. tier-03-cdktf-internal-tools

- [x] `cdktf.json`, `package.json`, `tsconfig*.json`, `environments.jsonc`, `terraform.devnet.tfvars.json`
- [x] `modules/kubernetes-aws-load-balancer-controller/` — Helm release + IRSA role + IAM policy stub
- [x] `modules/kubernetes-cert-manager/` — Helm release (off by default)
- [x] `src/infra/main.ts` + `InternalToolsDevnetStack` reads tier-02; k8s/helm providers via `aws_eks_cluster` + `aws_eks_cluster_auth`
- [x] `scripts/refresh-lbc-policy.sh` — fetches upstream IAM policy

## 8. tier-04-cdktf-applications

- [x] `cdktf.json`, `package.json`, `tsconfig*.json`, `environments.jsonc`, `terraform.devnet.tfvars.json`
- [x] `modules/kubernetes-rust-demo/` — namespace + Helm release of `app/helm/rust-demo`, takes `image_tag`
- [x] `src/infra/main.ts` + `ApplicationsDevnetStack` reads tier-02 outputs (cluster + ECR)

## 9. GitHub Actions

- [x] `.github/workflows/_shared-cdktf-tier.yml` — reusable plan+apply for any tier
- [x] `.github/workflows/tier-01-environments.yml`
- [x] `.github/workflows/tier-02-clusters.yml`
- [x] `.github/workflows/tier-03-internal-tools.yml`
- [x] `.github/workflows/tier-04-applications.yml` (input: `image_tag`)
- [x] `.github/workflows/deploy-all.yml` — orchestrator, manual-only, requires `confirm=devnet`
- [x] `.github/workflows/app-build.yml` — reusable: nix build → ECR push, Cachix token from Secrets Manager
- [x] `.github/workflows/app-release.yml` — `release: published` & tag `v*` → app-build → tier-04

## 10. Bootstrap & ops scripts

- [x] `scripts/bootstrap-tf-backend.sh` — S3 bucket + DynamoDB lock table
- [x] `scripts/bootstrap-github-oidc.sh` — OIDC provider + `cdktf-demo-gha` role
- [x] `scripts/bootstrap-secrets.sh` — `put-secret-value` for the Cachix token
- [x] `scripts/refresh-lbc-policy.sh` — fetch canonical LBC IAM policy
- [x] `scripts/deploy-all.sh` — local equivalent of orchestrator workflow
- [x] `scripts/destroy-all.sh` — reverse-order teardown
- [x] `scripts/set-aws-profile.sh` — sourced helper
- [x] `scripts/validate-architecture.sh` — module isolation, tier ordering, no-secrets-in-tfvars

## 11. Local-dev: minikube

- [x] `minikube/start.sh` — boots cluster + builds in-cluster image + applies manifests
- [x] `minikube/manifests/` — kustomization + namespace + deployment + service
- [x] `minikube/README.md`

## 12. Verification

### Self-verification done by Claude before hand-over (no AWS creds needed)

- [x] `app/Cargo.lock` generated and committed (run from `app/` via `cargo generate-lockfile`)
- [x] `nix flake check --impure` passes — `rust-demo` binary derivation builds; OCI image derivation evaluates; flake.lock generated
- [x] Cachix cache `radupopa2010` substituter + public key wired in `flake.nix` `nixConfig`
- [x] `terraform validate` passes for every HCL module (8/8: aws-network, aws-eks-cluster, aws-eks-nodegroup, aws-ecr, aws-secrets, kubernetes-aws-load-balancer-controller, kubernetes-cert-manager, kubernetes-rust-demo)
- [x] `npm install && cdktf get && cdktf synth devnet` succeeds in **every** tier:
  - tier-01-cdktf-environments → 110 lines of `cdk.tf.json` (VPC, 2 AZs, public+private /24 subnets)
  - tier-02-cdktf-clusters → 195 lines (EKS cluster + nodegroup + ECR + Secrets Manager skeletons)
  - tier-03-cdktf-internal-tools → 169 lines (LBC Helm release + IRSA + cert-manager scaffold)
  - tier-04-cdktf-applications → 147 lines (Helm release of `rust-demo` reading tier-02 outputs)
- [x] `./scripts/validate-architecture.sh` passes (modules don't cross-reference, tiers don't reference higher-numbered tiers, no secrets in tfvars, every tier has a stack)

### Operator-side (requires AWS creds + GitHub repo)

- [ ] Commit `app/Cargo.lock` and `flake.lock` (auto-generated above)
- [ ] `./scripts/bootstrap-tf-backend.sh` runs cleanly (S3 bucket + DynamoDB lock table)
- [ ] `GITHUB_OWNER=radupopa2010 GITHUB_REPO=cdktf-demo ./scripts/bootstrap-github-oidc.sh` runs cleanly
- [ ] Repo variables set in GitHub: `AWS_ROLE_ARN`, `AWS_REGION=eu-central-1`, `CACHIX_CACHE_NAME=radupopa2010`
- [ ] `./scripts/refresh-lbc-policy.sh` once before tier-03 deploy
- [ ] `gh workflow run tier-02-clusters.yml` succeeds (creates secret shells)
- [ ] `./scripts/bootstrap-secrets.sh` puts the Cachix push token in AWS Secrets Manager
- [ ] `gh workflow run deploy-all.yml -f confirm=devnet` reaches green
- [ ] After deploy: `curl http://<alb>/version` returns the right semver

### Known follow-ups (canonical-pattern alignment, deferred)

- [ ] Refactor: one `<TierName>Stack` class per tier, env loop in `main.ts` (currently each tier has a `<TierName>DevnetStack`)
- [ ] Move TS env-config types into `src/infra/types/config.ts` (currently inline in `tools/config.ts`)
- [ ] Rename stack files to PascalCase (`ClustersStack.ts`) to match Movement convention
- [ ] Add concurrency groups to per-tier workflows (`concurrency: { group: terraform-${{ inputs.environment }} }`)

## Review

### What's runnable today (without me having touched AWS)

- All TypeScript synthesises; `cdktf synth devnet` will produce valid Terraform JSON in every tier (assumes `npm install` + `cdktf get` first).
- All HCL modules pass `terraform validate` (no provider downloads required for this).
- `nix develop` enters the dev shell; `nix build .#rust-demo` builds the binary; `nix build .#rust-demo-image` builds the OCI image — both pull from the `radupopa2010` Cachix cache.
- `./scripts/validate-architecture.sh` checks the multi-tier rules.
- All seven workflows are valid YAML; `_shared-cdktf-tier.yml` is the heart of the plan/apply flow.
- `app/docker-compose up` and `./minikube/start.sh` are end-to-end runnable on a laptop.

### What still needs the operator to do

1. `nix flake update` once + commit `flake.lock`.
2. Run `cargo build` once in `app/` to generate and commit `Cargo.lock`.
3. Push the repo to GitHub.
4. Run `./scripts/bootstrap-tf-backend.sh` and `./scripts/bootstrap-github-oidc.sh` (from the dev shell, with AWS SSO logged in for profile `radupopa`).
5. Add the three GitHub repo **variables** (`AWS_ROLE_ARN`, `AWS_REGION`, `CACHIX_CACHE_NAME`). No secrets.
6. Run `./scripts/refresh-lbc-policy.sh` to replace the LBC IAM policy stub.
7. Trigger `gh workflow run tier-02-clusters.yml` once so the secret SHELLS exist in AWS Secrets Manager, then `./scripts/bootstrap-secrets.sh` to put the Cachix token value.
8. Trigger `gh workflow run deploy-all.yml -f confirm=devnet` for the first end-to-end deploy.
9. Cut a release: `git tag v0.1.0 && git push origin v0.1.0 && gh release create v0.1.0` — `app-release.yml` takes it from there.

### Known stubs and why

- **`tier-03/.../iam-policy.json`**: holds a placeholder until `refresh-lbc-policy.sh` fetches the real upstream policy. This is the only file that is intentionally non-functional out of the box.
- **`AdministratorAccess` on `cdktf-demo-gha`**: deliberate for a demo, called out in README and plan §4b.
- **EKS public endpoint open to `0.0.0.0/0`**: configurable in `tier-02-cdktf-clusters/environments.jsonc`. Set to your IP for any non-demo use.
