{
  description = "Nix flake that pushes a container with webshell into Snowpark Container Services";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs.follows = "nixpkgs-stable";

    snowcli = {
      url = "github:sfc-gh-vtimofeenko/snowcli-nix-flake";

      inputs = {
        nixpkgs-unstable.follows = "nixpkgs-unstable";
        nixpkgs-stable.follows = "nixpkgs-stable";
        nixpkgs.follows = "nixpkgs";
        # development
        devshell.follows = "devshell";
        pre-commit-hooks-nix.follows = "pre-commit-hooks-nix";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nixpkgs-stable.follows = "nixpkgs-stable";
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
            overlays = [ inputs.snowcli.overlays.default ];
            config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "snowsql" ];
          };
        in
        {
          packages = rec {
            ttydContainer = import ./packages/ttydContainer/package.nix {
              targetPkgs = spcsTargetPkgs;
              inherit self;
            };
            default = ttydContainer;
          };
          apps.buildAndPushToSpcs = import ./apps/buildAndPushToSpcs { inherit pkgs; };

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
                settings.configuration.MD041 = false;
              }; # Disable "first line should be a heading check"
            };
          };

          devShells.pre-commit = config.pre-commit.devShell;
          devshells.default = {
            env = [ ];
            commands = [ ];
            packages = builtins.attrValues { inherit (pkgs) jc jq skopeo; };
          };
        };
    };
}
