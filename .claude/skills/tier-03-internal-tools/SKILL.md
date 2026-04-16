---
name: tier-03-internal-tools
description: Cluster platform tier — AWS Load Balancer Controller and cert-manager. Use when changing ingress/cert behaviour or adding a new cluster-wide platform component.
---

## Scope

Owns cluster-platform components that the app tier (04) depends on but doesn't manage itself:

- **AWS Load Balancer Controller** (Helm) with IRSA — turns Kubernetes `Ingress` resources into ALBs automatically
- **cert-manager** (Helm, optional but scaffolded) — for future TLS automation

## Key files

| Path | Purpose |
|---|---|
| `tier-03-cdktf-internal-tools/modules/kubernetes-aws-load-balancer-controller/` | LBC Helm release + IRSA role + IAM policy JSON |
| `tier-03-cdktf-internal-tools/modules/kubernetes-cert-manager/` | cert-manager Helm release |
| `tier-03-cdktf-internal-tools/src/infra/main.ts` | Reads tier-02 remote state (cluster + OIDC) |

## How to test

```bash
cd tier-03-cdktf-internal-tools
npm install
npm run typecheck
cdktf synth devnet
```

## Provider configuration

Tier 03 uses `kubernetes` and `helm` providers, authenticated via `aws_eks_cluster` + `aws_eks_cluster_auth` data sources (NOT static kubeconfig). Pattern:

```hcl
data "aws_eks_cluster" "this" { name = var.cluster_name }
data "aws_eks_cluster_auth" "this" { name = var.cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
```

## How to modify

| Change | Where |
|---|---|
| Bump LBC chart version | `modules/kubernetes-aws-load-balancer-controller/main.tf` → `helm_release.version` |
| Update LBC IAM policy | Refresh JSON from <https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json> |
| Enable cert-manager | Set `enable_cert_manager = true` in `terraform.devnet.tfvars.json` |
| Add ClusterIssuer | New file under `modules/kubernetes-cert-manager/` (only after cert-manager is enabled) |

## Common issues

- **LBC pods CrashLoopBackOff with `AccessDenied`** — IAM policy out of date or trust policy missing the SA. Re-check IRSA role.
- **Ingress doesn't create an ALB** — public subnets in tier-01 missing `kubernetes.io/role/elb=1` tag (or LBC not running).
- **Stuck Helm release** — `helm rollback` then re-`cdktf deploy`. Don't manually `kubectl delete` the controller.
