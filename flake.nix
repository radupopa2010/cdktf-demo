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

        # ── Cross-compiled static binary for x86_64-linux-musl ──────────
        # Builds FROM any host (including aarch64-darwin) WITHOUT a Linux
        # builder VM. Uses Rust's built-in cross-compilation + a musl
        # cross-compiler from nixpkgs. The resulting binary is statically
        # linked and runs on any x86_64 Linux (including CI runners and
        # EKS nodes). Reference: https://crane.dev/examples/cross-musl.html
        crossToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" ];
          targets = [ "x86_64-unknown-linux-musl" ];
        };
        crossCraneLib = (crane.mkLib pkgs).overrideToolchain crossToolchain;
        crossArgs = commonArgs // {
          CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
          CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static -C link-self-contained=no";
          HOST_CC = "${pkgs.stdenv.cc.nativePrefix}cc";
        } // (if pkgs.stdenv.isLinux then {
          depsBuildBuild = [ pkgs.pkgsCross.musl64.stdenv.cc ];
          TARGET_CC = "${pkgs.pkgsCross.musl64.stdenv.cc}/bin/${pkgs.pkgsCross.musl64.stdenv.cc.targetPrefix}cc";
        } else {
          # On macOS: use zig as a cross-linker (works without a Linux VM)
          depsBuildBuild = [ pkgs.zig ];
          TARGET_CC = "zig cc -target x86_64-linux-musl";
          CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER = "${pkgs.writeShellScriptBin "zig-cc" ''exec zig cc -target x86_64-linux-musl "$@"''}/bin/zig-cc";
          # Zig needs a writable cache dir; the Nix sandbox's $HOME is read-only
          ZIG_GLOBAL_CACHE_DIR = "/tmp/zig-cache";
        });
        crossCargoArtifacts = crossCraneLib.buildDepsOnly crossArgs;
        rust-demo-linux-amd64 = crossCraneLib.buildPackage (crossArgs // {
          cargoArtifacts = crossCargoArtifacts;
          pname = "rust-demo";
          doCheck = false;
        });

        # OCI image from the cross-compiled binary — genuine linux/amd64,
        # buildable on Mac without a VM.
        rust-demo-image-amd64 = pkgs.dockerTools.buildLayeredImage {
          name = "rust-demo";
          tag = "latest";
          architecture = "amd64";
          contents = [ pkgs.cacert pkgs.tzdata ];
          config = {
            Entrypoint = [ "${rust-demo-linux-amd64}/bin/rust-demo" ];
            ExposedPorts = { "8080/tcp" = { }; };
            Env = [
              "RUST_LOG=info"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        # ── Host-native OCI image (for CI, which is already linux/amd64) ──
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
          inherit rust-demo rust-demo-image rust-demo-linux-amd64 rust-demo-image-amd64;
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
