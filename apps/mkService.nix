{ pkgs, ... }:
{
  program = pkgs.writeShellApplication {
    name = "buildAndPushToSpcs";
    runtimeInputs = [ pkgs.skopeo ];
    # Needs from environment:
    # * IMAGE_TAG
    # * REGISTRY_URL
    # * snowcli config capable of creating a service
    text = ''
      set -x
      snow sql -f ${./mk-service.sql} \
        -D "registry_url=$REGISTRY_URL"\
        -D "image_tag=$IMAGE_TAG"
    '';
  };
}
