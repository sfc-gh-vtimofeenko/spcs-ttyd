{
  description = "Nix flake that pushes a container with webshell into Snowpark Container Services";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs.follows = "nixpkgs-stable";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      imports = [
        inputs.devshell.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        { config
        , pkgs
        , # These inputs are unused in the template, but might be useful later
          # , self'
          # , inputs'
          # , system
          ...
        }:
        let
          spcsTargetSystem = "x86_64-linux";
          spcsTargetPkgs = import inputs.nixpkgs {
            system = spcsTargetSystem;
            config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "snowsql" ];
          };
        in
        {
          packages = rec {
            ttydContainer = import ./packages/ttydContainer/package.nix {
              targetPkgs = spcsTargetPkgs;
              inherit self;
            };
            snowflake-odbc = pkgs.callPackage ./packages/snowflake-odbc/package.nix {
              inherit (pkgs) fetchurl stdenv;
            };
            demoRunSQLas = pkgs.writeShellApplication {
              name = "run-sql-as";

              runtimeInputs = [ ];

              text = builtins.readFile ./demos/sql-query-runner/runme-nix;
            };
            default = ttydContainer;
          };

          apps = {
            buildAndPushToSpcs = import ./apps/buildAndPushToSpcs { inherit pkgs; };
            mkService = import ./apps/mkService.nix { inherit pkgs; };
          };

          # Development configuration
          treefmt = {
            programs = {
              nixpkgs-fmt.enable = true;
              deadnix = {
                enable = true;
                no-lambda-arg = true;
                no-lambda-pattern-names = true;
                no-underscore = true;
              };
              statix.enable = true;
            };
            projectRootFile = "flake.nix";
          };

          pre-commit.settings = {
            hooks = {
              treefmt = {
                enable = true;
                package = config.treefmt.build.wrapper;
              };
              deadnix = {
                enable = true;
                settings.edit = true;
              };
              statix = {
                enable = true;
                settings = {
                  ignore = [ ".direnv/" ];
                  format = "stderr";
                };
              };
              yamllint.enable = true;
              markdownlint = {
                enable = true;
                settings.configuration = {
                  MD041 = false; # Disable "first line should be a heading check"
                  MD013.code_blocks = false; # disable line length check in code blocks
                };
              };
            };
          };

          devShells.pre-commit = config.pre-commit.devShell;
          devshells.default = {
            env = [ ];
            commands = [ ];
            packages = builtins.attrValues {
              inherit (pkgs)
                jq
                skopeo
                act
                ;
            };
          };
        };
    };
}
