{ pkgs, ... }:
{
  program = pkgs.writeShellApplication {
    name = "buildAndPushToSpcs";
    runtimeInputs = [ pkgs.skopeo ];
    # Needs from environment:
    # * IMAGE_TAG
    # * REGISTRY_URL
    # * snowcli config capable of creating an spcs token
    text = ''
      set -x

      export FULL_TAG="$REGISTRY_URL/$IMAGE_TAG:latest"
      export REGISTRY_AUTH_FILE="/tmp/auth.json" # W/a for skopeo auth file, see https://github.com/containers/image/issues/1097
      IMAGE="target/nixBuiltImage" # Temporary build location

      nix build -o "''${IMAGE}" .#"''${1}"

      # Disable logging sensitive information
      set +x
      # This uses keypair auth
      snow spcs image-registry token --format=JSON | skopeo login "$REGISTRY_URL" --username 0sessiontoken --password-stdin
      set -x

      cat ''${IMAGE} | skopeo copy \
              --insecure-policy \
              --additional-tag "''${FULL_TAG,,}" `# ",," is a lowercase string bashism` \
              docker-archive:/dev/stdin `` \
              docker://"''${FULL_TAG,,}"
    '';
  };
}
