---
name: tier-04-applications
description: Application tier — deploys the Rust demo app via Helm, exposes it via ALB Ingress. Use when changing app deployment shape, image tag, or ingress.
---

## Scope

Owns the deployment of the `rust-demo` app:

- `helm_release` of the chart at `app/helm/rust-demo/`
- Inputs: `image_tag` (default `latest`, overridden by app-release workflow with the git tag), replicas, resource limits
- The chart's Ingress is annotated for the AWS Load Balancer Controller (`alb.ingress.kubernetes.io/scheme=internet-facing`, `target-type=ip`)

## Key files

| Path | Purpose |
|---|---|
| `tier-04-cdktf-applications/modules/kubernetes-rust-demo/` | Helm release wrapper |
| `tier-04-cdktf-applications/src/infra/main.ts` | Reads tier-02 (ECR URL) + tier-03 (LBC ready signal) |
| `app/helm/rust-demo/values.yaml` | Defaults (replicas, image repo, port 8080, ALB annotations) |

## How to test

```bash
cd tier-04-cdktf-applications
npm install
npm run typecheck
cdktf synth devnet
```

## How to modify

| Change | Where |
|---|---|
| Bump deployed image | Pass `-var image_tag=v1.2.3` (workflow does this on release) |
| Change replicas | `terraform.devnet.tfvars.json` → `app.replicas` |
| Add an Ingress path | `app/helm/rust-demo/templates/ingress.yaml` |
| Add a ConfigMap / env var | `app/helm/rust-demo/templates/deployment.yaml` (and `values.yaml`) |
| Pull a secret into the pod | Use External Secrets Operator (not yet installed) — or `kubernetes_secret` data source from a secret created in tier-02 |

## Image tag flow

1. Operator cuts a release `vX.Y.Z` on GitHub.
2. `app-release.yml` triggers `app-build.yml` → builds with Nix, tags + pushes `${ECR_REPO}:vX.Y.Z` and `${ECR_REPO}:latest`.
3. `app-release.yml` then dispatches `tier-04-applications.yml` with input `image_tag=vX.Y.Z`.
4. Tier-04 workflow runs `cdktf deploy devnet -var image_tag=vX.Y.Z`.
5. `helm_release` notices the change → rolling update.

## Verification after deploy

```bash
kubectl --context cdktf-demo-devnet get deploy,po,ing -n rust-demo
ALB=$(kubectl get ing rust-demo -n rust-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s "http://$ALB/version"     # → {"version":"X.Y.Z","commit":"<sha>"}
curl -sI "http://$ALB/health"     # → 200 OK
```

## Common issues

- **Ingress hostname empty** — LBC not running (tier-03 not deployed) or subnets missing tags.
- **`ImagePullBackOff`** — image tag doesn't exist in ECR (build workflow failed silently). Check Actions logs.
- **Pods on the wrong node group** — the chart's `nodeSelector`/`tolerations` must match the dedicated node group's labels/taints from tier-02.
