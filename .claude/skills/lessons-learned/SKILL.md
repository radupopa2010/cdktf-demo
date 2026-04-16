---
name: lessons-learned
description: Hard-won bugs and gotchas encountered while building and deploying this project. Read this BEFORE making changes to workflows, CDKTF stacks, Helm charts, Nix flakes, or EKS config — every entry is a mistake that already happened once.
---

## GitHub Actions

### 1. `release.published` reads workflow YAML from the TAG's commit, not main HEAD

When `gh release create vX.Y.Z` fires `app-release.yml`, GitHub checks out the workflow file at the **tag's ref**. If the tag was created before a workflow fix was pushed to main, the fix won't take effect.

**Always:** push the fix to main FIRST, then tag at HEAD, then create the release. If you forgot: `git tag -d vX && git push origin :refs/tags/vX && git tag -a vX -m "..." && git push origin vX`, then delete + recreate the release.

### 2. Workflow sidebar names come from `name:` inside YAML, not the filename

Renaming a file from `tier-01.yml` to `infra-tier-01.yml` does NOT update the Actions sidebar. You must also change the `name:` field at the top of the YAML.

### 3. `paths:` filters including `.github/workflows/` re-fire every tier on workflow-file edits

Each tier had `.github/workflows/_infra-shared-cdktf-tier.yml` in its `paths:` filter. Every push that touched ANY workflow file re-triggered all four tier deploys. Fixed by removing workflow paths from the filter — only actual infra code changes (`tier-XX-cdktf-*/**`) should trigger deploys.

### 4. `tee` masks exit codes — always use `set -eo pipefail`

`cdktf deploy ... 2>&1 | tee logs/deploy.log` — if cdktf fails, `tee` succeeds and the step reports green. Without explicit `set -eo pipefail` in the `shell: bash` block, GitHub Actions defaults can let this through. This caused a deploy failure to appear as "success" with a green checkmark. One run showed "Live deployment verified" in the Step Summary while the script had actually printed `❌ ALB hostname never appeared`.

### 5. Dual triggers cause racing pipelines

`app-release.yml` originally triggered on BOTH `release: published` AND `push: tags v*`. Running `gh release create vX.Y.Z` pushes the tag AND fires the release event — two pipelines race for the same DynamoDB state lock, one fails. Fixed: use only `release: published`.

### 6. `sed` global deletes can nuke critical lines

`sed -i '' '/.github\/workflows\//d'` was meant to remove paths: filter entries but also deleted the `uses: ./.github/workflows/...` line that calls the reusable workflow. All three tier workflows were broken (no job body). Always verify with `grep` after bulk sed operations.

### 7. Action version bumps need verification — not every `@vN` exists

Bumped `aws-actions/amazon-ecr-login@v2` to `@v3` assuming it existed. It didn't. Build failed with `Unable to resolve action`. Always check the action's GitHub releases page before bumping.

## CDKTF / Terraform

### 8. cdktf-cli 0.21 var flag is `--var=key=value`, not `-var key=value`

Terraform-style `-var key=value` (single dash) is silently ignored by cdktf-cli. The correct syntax is `--var=image_tag=v0.1.3` (two dashes, equals sign). The silence means no error, no warning — the variable just gets its default value. This kept the Helm release stuck on `image_tag=latest` for three release attempts.

### 9. `cdktf.json` filename shadows the `cdktf` npm package

With `tsconfig-paths` registered and `baseUrl: "."` + `resolveJsonModule: true` in tsconfig, `require('cdktf')` can resolve to `./cdktf.json` (the project config file) instead of `node_modules/cdktf`. This causes `cdktf.TerraformProvider` to be `undefined` at runtime. Fixed by using a custom `register-paths.js` that calls `tsconfig-paths.register()` with `addMatchAll: false`.

### 10. `cdktfRelativeModules` context required for local module paths

`TerraformHclModule` with `source: "./modules/..."` needs `cdktfRelativeModules` in the App context (or in `cdktf.json` `context`). Without it, cdktf errors with "the cdktfRelativeModules context is not set".

### 11. AWS provider pinning: cdktf.json `>=5.50.0` pulls v6, which breaks the EKS module v20

The EKS community module v20 references `elastic_gpu_specifications` which was removed in AWS provider v6. Pin to `~> 5.50` (or exact like `=5.100.0`) in both `cdktf.json` and module HCL `required_providers`.

## Helm

### 12. Helm `set { }` blocks → `set = [...]` attribute in helm provider 3.x

Helm provider 2.x uses the block syntax `set { name = "x"; value = "y" }`. Provider 3.x replaced it with an attribute list `set = [{ name = "x", value = "y" }]`. Using the wrong syntax gives `Unsupported block type` or `Unsupported argument`. Check which version your `cdktf.json` pins.

### 13. Helm resource names are `<release>-<chart>`, not just `<release>`

The Helm chart's `_helpers.tpl` generates fullname as `<release>-<chart>`. So release=`rust-demo`, chart=`rust-demo` → Ingress named `rust-demo-rust-demo`. Scripts that look for `rust-demo` get "not found". Either set `fullnameOverride` in values.yaml or use the actual doubled name.

## EKS

### 14. Single node group with taints blocks CoreDNS / kube-proxy

If the ONLY node group has a `NoSchedule` taint, CoreDNS and kube-proxy pods can't schedule anywhere → EKS addon stuck in `DEGRADED` → deploy times out after 20 min. Either: (a) add a second untainted "system" node group, or (b) drop the taint on the single group and use `nodeSelector` labels only for app placement.

### 15. AWS SSO roles need full path ARN for EKS access entries

`aws eks create-access-entry` rejects `arn:aws:iam::<acct>:role/<role-name>` for SSO-managed roles. The full ARN includes the path: `arn:aws:iam::<acct>:role/aws-reserved/sso.amazonaws.com/<region>/<role-name>`. Find it with: `aws iam list-roles --path-prefix /aws-reserved/sso.amazonaws.com/ --query "Roles[?RoleName=='<name>'].Arn"`.

### 16. EKS cluster creator admin is the CI role, not your SSO user

With `enable_cluster_creator_admin_permissions = true`, the principal that runs `terraform apply` (in our case, the GHA OIDC role `cdktf-demo-gha`) gets cluster admin. Your laptop's SSO user has no access until you manually `create-access-entry` + `associate-access-policy` for it.

## Nix

### 17. `dockerTools.buildLayeredImage` on macOS produces Mach-O binaries, not Linux ELF

On Apple Silicon, `nix build .#rust-demo-image` produces an arm64-darwin image. Docker on Mac tries to run it as linux/amd64 → `exec format error`. For local container validation on Mac, use `dev-pull.sh` (pulls the CI-built linux/amd64 image from ECR) or `dev-up.sh` in native mode (runs the Mach-O binary directly, no Docker).

### 18. `nix build .#rust-demo` only builds for the host system

`flake-utils.lib.eachDefaultSystem` creates per-system outputs but `nix build .#rust-demo` resolves to the current host's system only. To build for a different system (e.g., x86_64-linux from aarch64-darwin), you need a remote builder or `extra-platforms` configured.

## AWS / Bootstrap

### 19. S3 state bucket name includes account ID

`bootstrap-tf-backend.sh` creates `cdktf-demo-tfstate-<account-id>`. The CDKTF stacks read `CDKTF_STATE_BUCKET` env var. In CI, the shared workflow computes this from `aws sts get-caller-identity`. Locally, `.envrc` or `set-aws-profile.sh` should export it. If the env var isn't set, main.ts falls back to `cdktf-demo-tfstate` (wrong — bucket won't exist).

### 20. AWS profile `radupopa` doesn't exist in CI — default to empty

CDKTF stacks had `default: "radupopa"` for the `aws_profile` terraform variable. In CI (OIDC creds via env vars), there's no `~/.aws/config` with that profile → `failed to get shared config profile, radupopa`. Fixed: default to `""` (empty string), which makes the AWS provider fall through to the env-var credential chain.
