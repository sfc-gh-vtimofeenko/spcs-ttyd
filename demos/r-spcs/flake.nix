{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem =
        { self'
        , pkgs
        , ...
        }:
        {
          packages = rec {
            default = snowflake-odbc-driver;
            snowflake-odbc-driver = pkgs.callPackage ./snowflake-odbc-driver.nix { };
          };

          devShells.default = pkgs.stdenv.mkDerivation {
            name = "my-snowflake-odbc-project";
            buildInputs = [
              self'.packages.snowflake-odbc-driver
              pkgs.envsubst
            ];
            nativeBuildInputs = [
              pkgs.unixODBC
              (pkgs.rWrapper.override {

                packages = with pkgs.rPackages; [
                  DBI
                  dplyr
                  dbplyr
                  odbc
                ];
              })
            ];
            shellHook =
              let
                # This is the content of odbc.ini
                # "driver" directive allows directly passing .so from the nix store
                ODBCINI = pkgs.writeTextDir "odbc.ini" ''
                  [ODBC Data  Sources]
                  SnowflakeDSII = Snowflake

                  [SnowflakeDSII]
                  # This is populated from environment and is set by SPCS
                  SERVER = ''${SNOWFLAKE_HOST}
                  # This is populated from environment and is set by SPCS
                  account = ''${SNOWFLAKE_ACCOUNT}
                  Driver = ${self'.packages.snowflake-odbc-driver}/lib/libSnowflake.so
                  Port = 443
                  SSL = on
                  Locale = en-US
                  Tracing = 0
                  # Oauth stuff
                  authenticator=OAUTH
                  # Optional; token may expire and should be read when connecting
                  token= ''${SNOWFLAKE_TOKEN}
                '';
              in
              ''
                export SNOWFLAKE_TOKEN=$(cat /snowflake/session/token)
                envsubst < ${ODBCINI}/odbc.ini > ./odbc.ini
                # Looks like it needs to be in a writeable location?
                export ODBCINI=$(realpath ./odbc.ini)
              '';
          };
        };
    };
}
