---
name: rust-app
description: Build, run, and release the rust-demo axum app. Covers Nix build, Cachix usage, semver bumping, the docker-compose-based local validation flow, and the smoke-test against the cloud deployment.
---

## What the app does

Tiny axum HTTP server, two endpoints:

- `GET /version` → `{"version":"<CARGO_PKG_VERSION>","commit":"<GIT_COMMIT>"}`
- `GET /health` → `200 OK` (used by the ALB health check)

Listens on `0.0.0.0:8080`.

## Key files

| Path | Purpose |
|---|---|
| `app/Cargo.toml` | Crate metadata. `version = "X.Y.Z"` is the source of truth for `/version`. |
| `app/src/main.rs` | The two handlers + axum boilerplate. |
| `app/Cargo.lock` | Committed. Required for reproducible Nix builds. |
| `app/docker-compose.yml` | Local dev for app folk (no k8s). |
| `app/helm/rust-demo/` | Chart consumed by tier-04. |
| `flake.nix` (repo root) | Devshell + `packages.rust-demo` + `packages.rust-demo-image`. |

## Build commands

```bash
# Dev shell (rustc, cargo, cdktf, kubectl, helm, awscli, jq, gh)
nix develop

# Build the binary
nix build .#rust-demo
./result/bin/rust-demo &
curl localhost:8080/version

# Build the OCI image (loadable by docker)
nix build .#rust-demo-image
docker load < result
docker run --rm -p 8080:8080 rust-demo:latest
```

## Cachix flow (this is the demo!)

The cache is `radupopa2010` (owner: integer-it). Public key is baked into `flake.nix` so reads need no token.

**As a dev (local → CI)**

```bash
cachix use radupopa2010                  # read-only, no token needed
nix build .#rust-demo                    # local build
cachix authtoken <your-personal-token>   # only needed once for push
nix build .#rust-demo --print-out-paths | cachix push radupopa2010
# CI now skips re-building this derivation
```

**As CI (CI → local)**

The workflow loads the push token from AWS Secrets Manager (`cdktf-demo/devnet/cachix-radupopa2010-token`) after OIDC auth, then `cachix-action` watches the build and pushes new store paths automatically. After CI runs, any dev with `cachix use radupopa2010` can:

```bash
nix run github:<owner>/cdktf-demo#rust-demo   # downloads from cache, doesn't compile
```

That's the demo: **same artifact, no rebuild.**

## Semver bumping

1. Edit `app/Cargo.toml` `version = "X.Y.Z"` (semver: bump patch for fixes, minor for features, major for breaks).
2. `nix develop -c cargo build` to refresh `Cargo.lock`.
3. Commit both files: `git commit -am "app: bump to vX.Y.Z"`.
4. Tag and release:

   ```bash
   git tag -a vX.Y.Z -m "release X.Y.Z"
   git push origin vX.Y.Z
   gh release create vX.Y.Z --generate-notes
   ```

5. `app-release.yml` builds the image, pushes to ECR as `vX.Y.Z` + `latest`, then dispatches tier-04 with `image_tag=vX.Y.Z`.

## Local validation: dev-up.sh (Nix → Docker)

The whole point of the local flow is to prove "what runs here is what will run in EKS". The `app/docker-compose.yml` consumes the Nix-built OCI image (it does NOT rebuild from a Dockerfile — that would defeat the parity guarantee).

```bash
./scripts/dev-up.sh        # nix build → docker load → up → curl /version → assert
./scripts/dev-down.sh      # tear down the container
```

What the script asserts: the version returned by `/version` matches the version in `app/Cargo.toml`. If it doesn't, you forgot to rebuild after bumping (or the cache returned a stale path — unlikely with crane's input hashing).

## Cloud validation: smoke-test.sh

Same idea, against the live ALB. CI's `app-release` workflow runs this as its final job; you can also run it from your laptop:

```bash
aws eks update-kubeconfig --name cdktf-demo-devnet --region eu-central-1
./scripts/smoke-test.sh v0.1.1   # polls /version until it == 0.1.1
```

Exits non-zero if the version never matches — useful in CI's required-checks list.

## Common issues

- **`/version` returns 0.1.0 in prod, but Cargo.toml says 0.2.0** — image was built from an older commit. Re-tag and re-release.
- **`nix build` fails with "hash mismatch"** — `Cargo.lock` out of sync; run `cargo build` then commit.
- **Cachix push 401** — token expired or wrong secret value. Re-`bootstrap-secrets.sh`.
- **ALB health check failing** — `/health` returning non-200; check axum router order (most specific routes first in axum 0.7).
