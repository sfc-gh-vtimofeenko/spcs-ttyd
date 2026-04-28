{
  description = "Cortex Code CLI – Snowflake's AI coding assistant";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem =
        { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          cortex = pkgs.callPackage ./package.nix { };

          # Template written to the Nix store; $SNOWFLAKE_ACCOUNT and
          # $SNOWFLAKE_HOST are substituted at runtime via envsubst.
          connectionsTemplate = pkgs.writeText "connections.toml.tmpl" ''
            default_connection_name = "default"

            [default]
            account = "''${SNOWFLAKE_ACCOUNT}"
            host = "''${SNOWFLAKE_HOST}"
            authenticator = "OAUTH"
            token_file_path = "/snowflake/session/token"
          '';
        in
        {
          packages = {
            inherit cortex;
            default = cortex;
          };

          apps = {
            default = {
              type = "app";
              program = pkgs.lib.getExe cortex;
            };

            # Generates `~/.snowflake/connections.toml` from SPCS environment.
            # Exists as a separate app to prevent overwrites.

            mk-connections-toml = {
              type = "app";
              program = pkgs.lib.getExe (pkgs.writeShellApplication {
                name = "mk-connections-toml";
                runtimeInputs = [ pkgs.envsubst ];
                text = ''
                  : "''${SNOWFLAKE_ACCOUNT:?SNOWFLAKE_ACCOUNT must be set}"
                  : "''${SNOWFLAKE_HOST:?SNOWFLAKE_HOST must be set}"

                  out="$HOME/.snowflake/connections.toml"
                  mkdir -p "$(dirname "$out")"
                  envsubst < ${connectionsTemplate} > "$out"
                  echo "connections.toml written to $out"
                '';
              });
            };

            # Fetches the latest stable version from S3 and updates all
            # per-platform hashes in package.nix via nix-update.
            update-cortex = {
              type = "app";
              program = pkgs.lib.getExe (pkgs.writeShellApplication {
                name = "update-cortex";
                runtimeInputs = [
                  pkgs.curl
                  pkgs.nix-update
                ];
                text = ''
                  new=$(curl -fsSL \
                    "https://sfc-repo.snowflakecomputing.com/cortex-code-cli/a4643c4278/stable_version.txt" \
                    | tr -d '[:space:]')
                  echo "Updating to $new"
                  nix-update --version="$new" --system x86_64-linux   .#cortex
                  nix-update --version="$new" --system aarch64-linux  .#cortex
                  nix-update --version="$new" --system x86_64-darwin  .#cortex
                  nix-update --version="$new" --system aarch64-darwin .#cortex
                '';
              });
            };
          };
        };
    };
}
