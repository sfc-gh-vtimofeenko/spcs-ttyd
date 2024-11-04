{ pkgs, ... }:
{
  program = pkgs.writeShellApplication {
    name = "buildAndPushToSpcs";
    runtimeInputs = [ pkgs.skopeo ];
    text = ''
      # REGISTRY_URL, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD need to be provided from the environment.
      # In GH actions it can be done through variables/secrets.
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
