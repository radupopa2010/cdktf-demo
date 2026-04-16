---
name: tier-01-environments
description: Foundation tier — VPC, subnets, NAT, IGW for the cdktf-demo devnet. Use when adding/modifying networking primitives or onboarding a new region/environment.
---

## Scope

Owns the AWS-account-level **networking foundation** for the demo:

- One VPC per environment (currently only `devnet`)
- 2 public + 2 private subnets across 2 AZs (ALB needs ≥ 2)
- One Internet Gateway, **one** NAT Gateway (single — to keep cost low; comment in module says how to switch to one-per-AZ)
- Default route tables + S3 VPC gateway endpoint
- VPC tags consumed by EKS (`kubernetes.io/role/elb=1` on public subnets, `kubernetes.io/role/internal-elb=1` on private)

## Key files

| Path | Purpose |
|---|---|
| `tier-01-cdktf-environments/environments.jsonc` | Per-env config (regions, CIDR prefixes). devnet ACTIVE; others commented. |
| `tier-01-cdktf-environments/terraform.devnet.tfvars.json` | Devnet-specific overrides. |
| `tier-01-cdktf-environments/modules/aws-network/` | The actual VPC HCL module called from CDKTF. |
| `tier-01-cdktf-environments/src/infra/main.ts` | App entrypoint — instantiates `EnvironmentsDevnetStack`. |
| `tier-01-cdktf-environments/src/infra/tools/config.ts` | Loads `environments.jsonc` (jsonc-parser). |

## How to test

```bash
cd tier-01-cdktf-environments
npm install
npm run typecheck
cdktf synth devnet   # writes out/stacks/EnvironmentsDevnet/cdk.tf.json
cd modules/aws-network && terraform init -backend=false && terraform validate
```

## How to modify

| Change | Where |
|---|---|
| Add a region to devnet | `environments.jsonc` → `devnet.regions` array |
| Adjust CIDR | `environments.jsonc` → `devnet.networking.cidr_prefix` |
| Add a subnet tier (e.g., DB private) | `modules/aws-network/main.tf` + add an output |
| Switch to multi-AZ NAT (not cheap-mode) | `modules/aws-network/main.tf` — set `single_nat_gateway = false` on the registry vpc module |
| New environment (testnet) | Uncomment in `environments.jsonc`, add `terraform.testnet.tfvars.json`, add a stack class in `src/infra/main.ts` |

## Outputs (consumed by tier-02)

- `vpc_id`
- `vpc_cidr`
- `private_subnet_ids` (list)
- `public_subnet_ids` (list)
- `region`
- `azs` (list)

These are written to S3-backed Terraform state and read by tier-02 via `data "terraform_remote_state"`.

## Common issues

- **"Cannot find subnets for ALB"** — public subnets missing `kubernetes.io/role/elb=1` tag. Fix in module.
- **Cost spike** — accidentally enabled multi-AZ NAT. Single NAT is the demo default.
- **CIDR overlap with another env** — devnet uses `10.251.0.0/16` (matches the convention I used in the past). Don't reuse.
