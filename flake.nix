{
  description = "A simple Gradle 6 project";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  # this allows derivations with `__noChroot = true` and allows us to work around limitations with gradle
  # see https://zimbatm.com/notes/nix-packaging-the-heretic-way
  nixConfig.sandbox = "relaxed";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";

    flake-root.url = "github:srid/flake-root";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    gitignore = {
      url = "github:hercules-ci/gitignore.nix";
      # Use the same nixpkgs
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gradle2nix = {
      url = "github:numtide/gradle2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    flake-root,
    devshell,
    gitignore,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        inputs.flake-root.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem = {
        config,
        inputs',
        pkgs,
        lib,
        system,
        ...
      }: let
        inherit (pkgs) stdenv;

        jdk = pkgs.jdk17;
        gradle = pkgs.gradle;

        inherit (inputs.gradle2nix.packages.${system}) gradle2nix;
      in {
        # configure treefmt
        treefmt.config = {
          inherit (config.flake-root) projectRootFile;
          package = pkgs.treefmt;

          programs = {
            alejandra.enable = true;
          };
        };

        # allows us to run treefmt with `nix fmt`
        formatter = config.treefmt.build.wrapper;

        # define a devshell
        devShells.default = inputs'.devshell.legacyPackages.mkShell {
          env = with lib;
            mkMerge [
              [
                # Configure nix to use nixpgks
                {
                  name = "NIX_PATH";
                  value = "nixpkgs=${toString pkgs.path}";
                }
              ]
              (mkIf stdenv.isLinux [
                {
                  name = "JAVA_HOME";
                  eval = "$DEVSHELL_DIR/lib/openjdk";
                }
              ])
              (mkIf stdenv.isDarwin [
                # tbd
              ])
            ];

          packages = with lib;
            mkMerge [
              [
                jdk
                gradle
                gradle2nix
              ]
            ];
        };

        packages = let
          inherit (gitignore.lib) gitignoreSource;

          version = "1.0.0";
          src = gitignoreSource ./.;
        in {
          fod = let
            inherit (gitignore.lib) gitignoreSource;

            src = gitignoreSource ./.;
            version = "1.0.0";

            # fake build to pre-download deps into fixed-output derivation
            deps = stdenv.mkDerivation {
              pname = "vanilla-deps";
              inherit version src;

              nativeBuildInputs = [gradle pkgs.perl];

              buildPhase = ''
                export GRADLE_USER_HOME=$(mktemp -d)
                gradle --no-daemon installDist
              '';
              # perl code mavenizes paths (com.squareup.okio/okio/1.13.0/a9283170b7305c8d92d25aff02a6ab7e45d06cbe/okio-1.13.0.jar -> com/squareup/okio/okio/1.13.0/okio-1.13.0.jar)
              # reproducible by sorting
              installPhase = ''
                find $GRADLE_USER_HOME/caches/modules-2 -type f -regex '.*\.\(jar\|pom\)' \
                  | LC_ALL=C sort \
                  | perl -pe 's#(.*/([^/]+)/([^/]+)/([^/]+)/[0-9a-f]{30,40}/([^/\s]+))$# ($x = $2) =~ tr|\.|/|; "install -Dm444 $1 \$out/$x/$3/$4/$5" #e' \
                  | sh
              '';
              outputHashAlgo = "sha256";
              outputHashMode = "recursive";
              outputHash = "sha256-Om4BcXK76QrExnKcDzw574l+h75C8yK/EbccpbcvLsQ=";
            };
          in
            stdenv.mkDerivation rec {
              pname = "vanilla";
              inherit version src;

              nativeBuildInputs = [gradle pkgs.makeWrapper];

              # Point to our local deps repo
              gradleInit = pkgs.writeText "init.gradle" ''
                logger.lifecycle 'Replacing Maven repositories with ${deps}...'
                gradle.projectsLoaded {
                  rootProject.allprojects {
                    buildscript {
                      repositories {
                        clear()
                        maven { url '${deps}' }
                      }
                    }
                    repositories {
                      clear()
                      maven { url '${deps}' }
                    }
                  }
                }
                settingsEvaluated { settings ->
                  settings.pluginManagement {
                    repositories {
                      maven { url '${deps}' }
                    }
                  }
                }
              '';

              buildPhase = ''
                export GRADLE_USER_HOME=$(mktemp -d)
                gradle --offline --init-script ${gradleInit} --no-daemon installDist
              '';

              installPhase = ''
                mkdir -p $out/share/vanilla
                cp -r app/build/install/app/* $out/share/vanilla
                makeWrapper $out/share/vanilla/bin/app $out/bin/app \
                      --set JAVA_HOME ${jdk}
              '';

              meta.mainProgram = "app";
            };

          gradle2nix = let
            buildGradle = pkgs.callPackage ./gradle-env.nix {};
          in
            buildGradle {
              pname = "gradle2nix";
              inherit version src;

              envSpec = ./gradle-env.json;
              gradleFlags = ["installDist"];

              nativeBuildInputs = [pkgs.makeWrapper];

              installPhase = ''
                mkdir -p $out/share/gradle2nix
                cp -r app/build/install/app/* $out/share/gradle2nix
                ls -al $out/share/gradle2nix/bin/app
                makeWrapper $out/share/gradle2nix/bin/app $out/bin/app \
                   --set JAVA_HOME ${jdk}
              '';

              meta.mainProgram = "app";
            };

          yolo = stdenv.mkDerivation {
            pname = "yolo";
            inherit version src;

            # Disable the Nix build sandbox for this specific build.
            # This means the build can freely talk to the Internet.
            __noChroot = true;

            nativeBuildInputs = [gradle pkgs.makeWrapper];

            buildPhase = ''
              export GRADLE_USER_HOME=$(mktemp -d)
              gradle --no-daemon installDist
            '';

            installPhase = ''
              mkdir -p $out/share/vanilla
              cp -r app/build/install/app/* $out/share/vanilla
              makeWrapper $out/share/vanilla/bin/app $out/bin/app \
                    --set JAVA_HOME ${jdk}
            '';

            meta.mainProgram = "app";
          };
        };
      };
    };
}
