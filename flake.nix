{
  description = "cdktf-demo — Rust axum app + cdktf tooling, with shared Cachix cache (radupopa2010)";

  nixConfig = {
    # Reads from the shared Cachix cache without needing a token.
    extra-substituters = [
      "https://radupopa2010.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "radupopa2010.cachix.org-1:BjufnV1F5zRtjpzEBeV2GGt/04DOrQgq2glSyJKE9ZU="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    # crane (latest) requires nixpkgs >= 25.11 / unstable.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # crane no longer takes an `inputs.nixpkgs` to follow.
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, crane, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
          # Terraform moved to BSL-1.1 (unfree) at 1.6. We accept it for this
          # specific package only; nothing else falls through.
          config.allowUnfreePredicate = pkg:
            builtins.elem (pkgs.lib.getName pkg) [ "terraform" ];
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "clippy" "rustfmt" ];
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        appSrc = craneLib.cleanCargoSource ./app;

        commonArgs = {
          src = appSrc;
          strictDeps = true;
          # Inject git commit at build time so /version reports it.
          GIT_COMMIT = self.shortRev or self.dirtyShortRev or "unknown";
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        rust-demo = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
          pname = "rust-demo";
          # Tests run inside the dev shell, not in CI image build.
          doCheck = false;
        });

        # OCI image consumed by ECR. Tag is :latest by default; CI re-tags
        # with the git tag before pushing.
        rust-demo-image = pkgs.dockerTools.buildLayeredImage {
          name = "rust-demo";
          tag = "latest";
          contents = [ pkgs.cacert pkgs.tzdata ];
          config = {
            Entrypoint = [ "${rust-demo}/bin/rust-demo" ];
            ExposedPorts = { "8080/tcp" = { }; };
            Env = [
              "RUST_LOG=info"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        # cdktf is installed via npm in each tier (`npm install` brings it in
        # as a transitive of `cdktf-cli`). The devshell ships node + npm so
        # the operator can run `npx cdktf` from any tier directory without
        # depending on an upstream Nix package that drifts.
        devTools = with pkgs; [
          # Rust
          rustToolchain
          cargo-watch
          cargo-edit
          # CDKTF / Terraform
          terraform
          nodejs_20
          # Cloud
          awscli2
          kubectl
          kubernetes-helm
          # Misc
          jq
          yq-go
          gh
          git
          # Cachix CLI for the manual push flow
          cachix
        ];
      in
      {
        packages = {
          inherit rust-demo rust-demo-image;
          default = rust-demo;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = rust-demo;
          name = "rust-demo";
        };

        devShells.default = pkgs.mkShell {
          packages = devTools;
          shellHook = ''
            export AWS_PROFILE=''${AWS_PROFILE:-radupopa}
            export AWS_REGION=''${AWS_REGION:-eu-central-1}
            echo "cdktf-demo dev shell — AWS_PROFILE=$AWS_PROFILE region=$AWS_REGION"
            echo "  nix build .#rust-demo            # build the binary"
            echo "  nix build .#rust-demo-image      # build the OCI image"
            echo "  nix run                          # run the app"
            echo "  cachix use radupopa2010          # enable cache reads"
            echo "  (cd tier-XX-... && npm install)  # cdktf-cli arrives here"
          '';
        };

        formatter = pkgs.nixpkgs-fmt;

        checks = {
          inherit rust-demo;
        };
      });
}
