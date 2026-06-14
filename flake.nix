{
  description = "Rust Template - Best-in-class Rust project setup";
  inputs = {
    # LLM: Do NOT change this URL unless explicitly directed. This is the
    # correct format for nixpkgs stable (25.11 is correct, not nixos-25.11).
    nixpkgs.url = "github:NixOS/nixpkgs/25.11";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
    changelog-roller.url = "github:LoganBarnett/changelog-roller";
    foundation.url = "github:LoganBarnett/rust-template";
    foundation.inputs.nixpkgs.follows = "nixpkgs";
    org-fmt.url = "github:LoganBarnett/org-fmt";
    org-fmt.inputs.nixpkgs.follows = "nixpkgs";
    org-fmt.inputs.rust-overlay.follows = "rust-overlay";
    org-fmt.inputs.crane.follows = "crane";
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    crane,
    changelog-roller,
    foundation,
    org-fmt,
  } @ inputs: let
    forAllSystems =
      nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    perSystem = forAllSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [(import rust-overlay)];
      };
      craneLib =
        (crane.mkLib pkgs).overrideToolchain
        (p: p.rust-bin.stable.latest.default);
      rust = pkgs.rust-bin.stable.latest.default.override {
        extensions = [
          # For rust-analyzer and others.  See
          # https://nixos.wiki/wiki/Rust#Shell.nix_example for details.
          "rust-src"
          "rust-analyzer"
          "rustfmt"
        ];
      };
      crates = {
        # CRATE:cli:begin
        cli = {
          name = "first-food-cli";
          binary = "first-food-cli";
          description = "CLI application";
        };
        # CRATE:cli:end
        # CRATE:dev:begin
        dev = {
          name = "first-food-dev";
          binary = "first-food-dev";
          description = "Development tool (map editor)";
        };
        # CRATE:dev:end
        # CRATE:server:begin
        server = {
          name = "first-food-server";
          binary = "first-food-server";
          description = "Server process";
        };
        # CRATE:server:end
        # CRATE_ENTRIES

        # Note: The 'lib' crate is not included here as it doesn't
        # produce a binary.
      };
      commonArgs = {
        src = craneLib.cleanCargoSource self;
        # Run only unit tests (--lib --bins), skip integration tests in
        # tests/ directories.  Integration tests may require external
        # services not available in the Nix sandbox.
        cargoTestExtraArgs = "--lib --bins";
      };
      rustPackages = foundation.lib.mkRustPackages {
        inherit self pkgs craneLib crates commonArgs;
      };
      packages =
        rustPackages.packages
        // {
          default =
            craneLib.buildPackage (commonArgs // {pname = "first-food";});
        };
    in {
      inherit packages;
      inherit (rustPackages) apps;
      devShell = pkgs.mkShell {
        buildInputs = [
          # Rust toolchain (compiler, cargo, rustfmt, rust-analyzer).
          rust
          # Prunes stale per-profile artifacts from target/ to reclaim disk.
          pkgs.cargo-sweep
          # JSON parsing for the shellHook's cargo-package listing and ad-hoc
          # scripting in the dev shell.
          pkgs.jq
          # Elm toolchain for the frontend/ app: compiler, formatter, and the
          # elm2nix bridge that pins Elm deps for reproducible builds.
          pkgs.elmPackages.elm
          pkgs.elmPackages.elm-format
          pkgs.elm2nix
          # Unified formatter and the per-language binaries it invokes.
          pkgs.treefmt
          pkgs.alejandra
          pkgs.prettier
          # Command runner for the project's justfile recipes.
          pkgs.just
          # Rolls the CHANGELOG on release; used by the reusable CI workflow's
          # `changelog` job and runnable locally for the same flow.
          changelog-roller.packages.${system}.default
          # Formats org-mode documents (treefmt delegates .org files to it).
          org-fmt.packages.${system}.default
        ];
        shellHook = ''
          ${foundation.lib.cargoHuskyHookSnippet pkgs}
          # Send the informational banner to stderr so stdout stays clean for
          # commands run through `nix develop --command` (such as `just dev`).
          {
            echo "first-food development environment"
            echo ""
            echo "Available Cargo packages (use 'cargo build -p <name>'):"
            cargo metadata --no-deps --format-version 1 2>/dev/null | \
              jq --raw-output '.packages[].name' | \
              sort | \
              sed 's/^/  • /' || echo "  Run 'cargo init' to get started"

            echo ""
            echo "Elm frontend (frontend/):"
            echo "  Build:   cd frontend && elm make src/Main.elm --output public/elm.js"
            echo "  Format:  treefmt"
            echo "  After changing elm.json dependency versions, regenerate Nix files:"
            echo "    cd frontend"
            echo "    elm2nix convert 2>/dev/null > elm-srcs.nix"
            echo "    elm2nix snapshot"
            echo "    git add elm-srcs.nix registry.dat && git commit"
          } 1>&2
        '';
      };
    });
  in {
    devShells =
      nixpkgs.lib.mapAttrs (_: p: {default = p.devShell;}) perSystem;
    packages = nixpkgs.lib.mapAttrs (_: p: p.packages) perSystem;
    apps = nixpkgs.lib.mapAttrs (_: p: p.apps) perSystem;

    # ================================================================
    # NIXOS MODULES
    # ================================================================
    nixosModules = {
      server = import ./nix/modules/nixos-server.nix {
        inherit self foundation;
      };
      default = self.nixosModules.server;
    };

    # ================================================================
    # DARWIN MODULES
    # ================================================================
    darwinModules = {
      server = import ./nix/modules/darwin-server.nix {
        inherit self foundation;
      };
      default = self.darwinModules.server;
    };
  };
}
