{ pkgs, ... }:
{
  program = pkgs.writeShellApplication {
    name = "pushArchiveToSpcs";
    runtimeInputs = [
      pkgs.skopeo
      pkgs.snowflake-cli
    ];
    # Needs from environment:
    # * IMAGE_TAG
    # * REGISTRY_URL
    # * Snowflake connection env vars (SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER,
    #   SNOWFLAKE_AUTHENTICATOR, SNOWFLAKE_PRIVATE_KEY_PATH)
    # $1: path to docker archive (default: out)
    text = ''
      ARCHIVE="''${1:-out}"
      TAG="$REGISTRY_URL/$IMAGE_TAG:latest"

      # Disable logging sensitive information
      set +x
      snow spcs image-registry token --format=JSON \
        | skopeo login "$REGISTRY_URL" --username 0sessiontoken --password-stdin
      set -x

      skopeo copy \
        --additional-tag "$TAG" \
        --insecure-policy \
        docker-archive:"$ARCHIVE" \
        docker://"$TAG"
    '';
  };
}
