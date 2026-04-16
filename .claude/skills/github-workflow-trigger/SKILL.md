---
name: github-workflow-trigger
description: Dispatch and observe GitHub Actions workflows for the cdktf-demo. Use when triggering tier deploys, the orchestrator, or the app-release flow from the CLI.
---

## Prereq (one-time)

```bash
gh auth login           # browser flow, pick HTTPS, scope: repo + workflow
gh repo set-default     # pick this repo
```

## Workflows in this repo

| File | Trigger | Inputs | What it does |
|---|---|---|---|
| `tier-01-environments.yml` | `workflow_dispatch`, push to `main` under `tier-01-cdktf-environments/**` | — | `cdktf plan` + (on apply job) `cdktf deploy devnet` |
| `tier-02-clusters.yml` | same, scoped to tier-02 paths | — | EKS + ECR + secret skeletons |
| `tier-03-internal-tools.yml` | same, scoped to tier-03 paths | — | LBC + cert-manager |
| `tier-04-applications.yml` | `workflow_dispatch`, `repository_dispatch` (`image-released`) | `image_tag` (string) | Helm release of the app |
| `deploy-all.yml` | `workflow_dispatch` only | `confirm` (must equal `devnet`) | Calls tiers 01 → 04 sequentially via `workflow_call` |
| `app-build.yml` | `workflow_call` (reusable) | `image_tag` | Nix build → push to ECR → output digest |
| `app-release.yml` | `release: published`, `push: tags v*` | — | Calls `app-build`, then dispatches `tier-04-applications` |

## Common operations

### Trigger one tier

```bash
gh workflow run tier-02-clusters.yml --ref main
gh run watch                               # interactive
gh run view --log                          # latest run, full logs
```

### Trigger the orchestrator

```bash
gh workflow run deploy-all.yml --ref main -f confirm=devnet
gh run watch
```

### Trigger an app deploy with a specific tag

```bash
gh workflow run tier-04-applications.yml --ref main -f image_tag=v0.1.0
```

### Cut a release (the canonical way to deploy a new app version)

```bash
git tag -a v0.1.0 -m "first demo release"
git push origin v0.1.0
gh release create v0.1.0 --generate-notes
# app-release.yml fires automatically
```

### Inspect

```bash
gh run list --workflow=tier-02-clusters.yml --limit 5
gh run view <run-id> --log-failed                     # only failed steps
gh run download <run-id> -n cdktf-plan-tier-02        # plan artifact
```

### Re-run

```bash
gh run rerun <run-id>                 # re-run failed jobs only
gh run rerun <run-id> --failed
```

## Auth model recap (for debugging)

- Workflows have `permissions: { id-token: write, contents: read }`.
- Step `aws-actions/configure-aws-credentials@v4` exchanges the OIDC token for STS creds using `${{ vars.AWS_ROLE_ARN }}`.
- Real secrets (Cachix push token, etc.) are pulled **after** that step from AWS Secrets Manager via `aws secretsmanager get-secret-value`.
- **There are no GitHub Actions secrets in this repo.** Only repo variables: `AWS_ROLE_ARN`, `AWS_REGION`, `CACHIX_CACHE_NAME`.

## When a workflow fails

1. `gh run view <id> --log-failed` to find the failing step.
2. If it's `configure-aws-credentials` failing — check the OIDC trust policy on `cdktf-demo-gha`.
3. If it's `cdktf deploy` — pull the `cdktf-plan-*` artifact and read the diff.
4. If it's a Cachix step — verify the secret value with `aws secretsmanager get-secret-value --secret-id cdktf-demo/devnet/cachix-radupopa2010-token --profile radupopa`.

Never store a token in a GitHub secret to "fix it quickly". Add it to Secrets Manager.
