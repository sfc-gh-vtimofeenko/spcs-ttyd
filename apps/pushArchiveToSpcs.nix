{ pkgs, ... }:
{
  program = pkgs.writeShellApplication {
    name = "pushArchiveToSpcs";
    runtimeInputs = [
      pkgs.skopeo
    ];
    # Needs from environment:
    # * IMAGE_TAG
    # * REGISTRY_URL
    # * SNOWFLAKE_USER
    # * SNOWFLAKE_PAT: programmatic access token for SNOWFLAKE_USER
    # $1: path to docker archive (default: out)
    text = ''
      : "''${REGISTRY_URL:?REGISTRY_URL must be set}"
      : "''${IMAGE_TAG:?IMAGE_TAG must be set}"
      : "''${SNOWFLAKE_USER:?SNOWFLAKE_USER must be set}"
      # Fail early: an empty password makes skopeo fall back to an interactive prompt
      : "''${SNOWFLAKE_PAT:?SNOWFLAKE_PAT must be set}"
      ARCHIVE="''${1:-out}"
      TAG="$REGISTRY_URL/$IMAGE_TAG:latest"

      # Disable logging sensitive information
      set +x
      printf '%s' "$SNOWFLAKE_PAT" \
        | skopeo login "$REGISTRY_URL" --username "$SNOWFLAKE_USER" --password-stdin
      set -x

      skopeo copy \
        --additional-tag "$TAG" \
        --insecure-policy \
        docker-archive:"$ARCHIVE" \
        docker://"$TAG"
    '';
  };
}
