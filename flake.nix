{
  description = "Nix flake that pushes a container with webshell into Snowpark Container Services";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs.follows = "nixpkgs-stable";

    snowcli = {
      url = "github:sfc-gh-vtimofeenko/snowcli-nix-flake";

      inputs = {
        nixpkgs-unstable.follows = "nixpkgs-unstable";
        nixpkgs-stable.follows = "nixpkgs-stable";
        nixpkgs.follows = "nixpkgs";
        # Only using 2x in this flake
        snowcli-src-1x.follows = "";
        snowflake-connector-python-1x.follows = "";
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

  outputs = inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      imports = [
        inputs.devshell.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        { config
        , pkgs
          /* These inputs are unused in the template, but might be useful later */
          # , self'
          # , inputs'
          # , system
        , ...
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
          packages.ttydContainer = import ./packages/ttydContainer/package.nix { targetPkgs = spcsTargetPkgs; inherit self; };
          apps.buildAndPushToSpcs = import ./apps/buildAndPushToSpcs { inherit pkgs; };

          /* Development configuration */
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
              treefmt.enable = true;
              deadnix.enable = true;
              statix.enable = true;
              yamllint.enable = true;
              markdownlint.enable = true;
            };
            settings = {
              deadnix.edit = true;
              statix = {
                ignore = [ ".direnv/" ];
                format = "stderr";
              };
              markdownlint.config.MD041 = false; # Disable "first line should be a heading check"
              treefmt.package = config.treefmt.build.wrapper;
            };
          };

          devShells.pre-commit = config.pre-commit.devShell;
          devshells.default = {
            env = [ ];
            commands = [ ];
            packages = builtins.attrValues { inherit (pkgs) jc jq; };
          };
        };

      flake = { };
    };
}
