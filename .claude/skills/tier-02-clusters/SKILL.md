---
name: tier-02-clusters
description: Cluster tier — EKS control plane, dedicated node pool, ECR repo, IRSA OIDC provider, and the AWS Secrets Manager skeleton. Use when adding cluster add-ons, changing node sizing, or registering new secrets.
---

## Scope

Owns the cluster the demo app runs on, plus its image registry and secret skeletons:

- One EKS cluster (Kubernetes 1.30, public endpoint restricted to operator IP)
- One **dedicated** managed node group for the app — `t3.small`, min 1 / max 2 / desired 1
- IAM Role for Service Accounts (IRSA) OIDC provider for the cluster
- ECR repo `cdktf-demo/rust-demo` with image scanning + lifecycle policy (keep last 10)
- Secrets-Manager skeleton: `null_resource` creates each secret name idempotently; values are filled out-of-band

## Key files

| Path | Purpose |
|---|---|
| `tier-02-cdktf-clusters/environments.jsonc` | Per-env overrides for cluster (k8s version, node sizing). |
| `tier-02-cdktf-clusters/modules/aws-eks-cluster/` | EKS control plane (calls `terraform-aws-modules/eks/aws`). |
| `tier-02-cdktf-clusters/modules/aws-eks-nodegroup/` | App-dedicated node group (labels + taints). |
| `tier-02-cdktf-clusters/modules/aws-ecr/` | ECR repository for the rust image. |
| `tier-02-cdktf-clusters/modules/aws-secrets/` | `null_resource` skeleton creator. |
| `tier-02-cdktf-clusters/src/infra/main.ts` | App entrypoint; reads tier-01 remote state. |

## How to test

```bash
cd tier-02-cdktf-clusters
npm install
npm run typecheck
cdktf synth devnet
for m in modules/*/; do
  (cd "$m" && terraform init -backend=false && terraform validate)
done
```

## How to modify

| Change | Where |
|---|---|
| Bump k8s version | `environments.jsonc` → `devnet.cluster.version` |
| Resize app node group | `environments.jsonc` → `devnet.nodegroups.app.{instance_type,min,max,desired}` |
| Add a node group (e.g., system) | New module call in `src/infra/stacks/clusters-devnet.ts` |
| Add a managed add-on | EKS module input `cluster_addons` |
| Register a new secret name | Add to `modules/aws-secrets/variables.tf` default list, then `bootstrap-secrets.sh` |
| Change ECR repo name | `modules/aws-ecr/variables.tf` default, plus `app-build.yml` workflow env |

## Outputs (consumed by tier-03 and tier-04)

- `cluster_name`
- `cluster_endpoint`
- `cluster_ca_certificate` (base64)
- `cluster_oidc_provider_arn`
- `cluster_oidc_issuer_url`
- `node_role_arn`
- `app_node_group_name`
- `ecr_repo_url`

## Secrets contract

Secret names registered in `aws-secrets`:

- `cdktf-demo/devnet/cachix-radupopa2010-token` — Cachix push token (used by CI)

To add one: append to `var.secret_names` in tier-02, run `cdktf deploy devnet`, then put the value via `scripts/bootstrap-secrets.sh`.

## Common issues

- **`UnauthorizedOperation` creating EKS** — IRSA bootstrap role missing permissions; tighten IAM in `bootstrap-github-oidc.sh`.
- **Node group stuck in `CREATING`** — usually subnet capacity (single NAT, AZ has no IPs left). Check tier-01 subnet `/24`.
- **ECR push fails from CI** — workflow forgot `aws ecr get-login-password | docker login`. See `app-build.yml`.
- **`describe-secret` returns AccessDenied in `null_resource`** — operator profile is wrong; export `AWS_PROFILE=radupopa`.
