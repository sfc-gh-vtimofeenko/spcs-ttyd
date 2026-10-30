{ pkgs, self, ... }:
{
  program = pkgs.writeShellApplication {
    name = "buildAndPushToSpcs";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
      pkgs.skopeo
      # pkgs.snowflake-cli # comes from environment for now
    ];
    # Needs from environment:
    # * IMAGE_TAG
    # * REGISTRY_URL
    # * snowcli config capable of creating an spcs token
    text = ''
      : "''${IMAGE_TAG:?IMAGE_TAG must be set}"
      : "''${REGISTRY_URL:?REGISTRY_URL must be set}"
      export FULL_TAG="$REGISTRY_URL/$IMAGE_TAG:latest"
      export REGISTRY_AUTH_FILE="/tmp/auth.json" # W/a for skopeo auth file, see https://github.com/containers/image/issues/1097
      IMAGE_DIR="$(mktemp -d)"
      IMAGE="$IMAGE_DIR/image"
      trap 'rm -rf "$IMAGE_DIR"' EXIT

      nix build "${self}#''${1:?flake package name required}" -o "$IMAGE"

      # Disable logging sensitive information
      set +x
      # This uses keypair auth
      snow spcs image-registry token --format=JSON | skopeo login "$REGISTRY_URL" --username 0sessiontoken --password-stdin
      set -x

      skopeo copy \
        --insecure-policy \
        --additional-tag "''${FULL_TAG,,}" \
        "docker-archive:$IMAGE" \
        "docker://''${FULL_TAG,,}"
    '';
  };
}
