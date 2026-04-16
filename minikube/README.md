# Minikube — local infra-team flow

Run the full app stack on your laptop without touching AWS. For app-only dev (no Kubernetes), use `app/docker-compose.yml` instead.

## Prereqs

- `minikube` (`brew install minikube`)
- `docker` (Desktop or Colima)
- `kubectl` (in the Nix devshell — `nix develop`)

## Up

```bash
./minikube/start.sh
```

What it does:

1. Boots minikube with profile `cdktf-demo` (4 CPU / 6 GiB / ingress addon).
2. Points your shell's docker at minikube's docker, so `docker compose build` produces images the cluster can run without a registry.
3. Builds the rust-demo image via `app/docker-compose.yml`.
4. Applies the kustomization in `minikube/manifests/`.
5. Prints the service URL.

## Verify

```bash
kubectl get pods -n rust-demo
curl "$(minikube -p cdktf-demo service rust-demo --url)/version"
curl "$(minikube -p cdktf-demo service rust-demo --url)/health"
```

## Down

```bash
minikube -p cdktf-demo delete
```
