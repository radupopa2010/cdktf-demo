# cdktf-demo — Claude AI Guidelines

This is a **demo** project showing the multi-tier CDKTF pattern used at Movement Labs, scaled down to one environment (`devnet`) on AWS in `eu-central-1`. Read `plan.md` once at session start for the design; read `tasks.md` to see what's done.

## 🚨 Critical safety rules

1. **NEVER interrupt `cdktf` / `terraform` commands.** They take 10–30 minutes for VPC/EKS operations. State corruption is the cost of being impatient.
2. **Always check first:** `ps aux | grep -E "(cdktf|terraform)" | grep -v grep` before running anything in a tier.
3. **Always log:** every cdktf command must be piped to `tee <tier>/logs/cdktf-<cmd>-$(date +%Y%m%d-%H%M%S).log`. The `cdktf` skill (`.claude/skills/cdktf/SKILL.md`) wraps this.
4. **Never run cdktf from this conversation without confirming with the user.** This conversation is for code, not deploys. Deploys happen via GitHub Actions or by the user invoking the script.
5. **Never put secrets in `tfvars`, code, GitHub Actions secrets, or env files.** Secrets live in AWS Secrets Manager only. See `plan.md` §4a.

## Tier ownership

| Tier | Owns | Reads from | Skill |
|---|---|---|---|
| 01 environments | VPC, subnets, NAT, IGW | — | `tier-01-environments` |
| 02 clusters | EKS cluster, dedicated nodegroup, ECR, Secrets Manager skeletons, IRSA OIDC | tier-01 | `tier-02-clusters` |
| 03 internal-tools | AWS Load Balancer Controller, cert-manager | tier-02 | `tier-03-internal-tools` |
| 04 applications | Helm release of `rust-demo`, Ingress (ALB) | tier-02, tier-03 | `tier-04-applications` |

**Lower tiers must be deployable without higher tiers existing.** Higher tiers consume lower-tier outputs via `terraform_remote_state` (S3 backend).

## Naming conventions

- Resources: `{component}-{environment}-{region}` → `rust-demo-devnet-eu-central-1`
- Tags on every AWS resource: `Project=cdktf-demo`, `Env=devnet`, `Tier=N-{name}`, `ManagedBy=cdktf`
- Module dirs use kebab-case: `aws-eks-cluster`, `kubernetes-aws-load-balancer-controller`
- Stack class names: `{Tier}{Env}Stack` → `EnvironmentsDevnetStack`

## Anti-patterns (do not do these)

- ❌ Module references another module — modules are isolated; only stacks compose them
- ❌ Higher-numbered tier consumed by lower-numbered tier
- ❌ Hardcoded values in modules — everything via `variables.tf`
- ❌ Secrets in `tfvars` / `helm-values` / `.env`
- ❌ Long-lived AWS keys in GitHub — only OIDC role
- ❌ Removing entries from `environments.jsonc` — comment them out instead (preserves the multi-env shape this project mirrors)
- ❌ Running `cdktf deploy` from this AI session

## Where to put things

- New cloud component: new module under `<tier>/modules/<name>/` (HCL: main.tf + variables.tf + outputs.tf)
- New tier: new top-level dir `tier-NN-cdktf-<name>/` + skill `.claude/skills/tier-NN-<name>/SKILL.md`
- New environment (testnet, mainnet later): uncomment the section in each `environments.jsonc`, add `terraform.<env>.tfvars.json`, add a stack instantiation in `src/infra/main.ts`
- New CI workflow: `.github/workflows/<purpose>.yml`, register in `deploy-all.yml` if it should run as part of orchestration
- New secret: add to inventory in `plan.md` §4a, list it in `tier-02/modules/aws-secrets/variables.tf`, document `aws secretsmanager put-secret-value` in `scripts/bootstrap-secrets.sh`

## Test / lint commands per tier

```bash
cd tier-XX-cdktf-...
npm install            # first time
npm run typecheck
npm run lint
cdktf synth devnet     # validates everything synthesizes
```

For HCL modules:

```bash
cd tier-XX-.../modules/<name>
terraform init -backend=false
terraform validate
terraform fmt -check
```

## Markdown standards

- MD022, MD031, MD032, MD047 enforced (headings/code/lists surrounded by blanks; file ends with single newline)
- Don't add AI-attribution to commit messages

## When you write commits in this repo

- Small, focused, one tier per commit when reasonable
- Subject ≤ 72 chars, conventional-ish: `tier-02: add ECR module`, `app: bump axum to 0.7.5`
- No `Co-Authored-By: Claude` footers, no AI attribution
