# Generates a registry.json file with pinned nixpkgs versions from flake inputs
# Effectively implements https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/nix-flakes.nix
{ inputs, ... }:
{
  stdenv,
  lib,
  writeText,
}:
stdenv.mkDerivation {
  name = "nix-registry";

  # Extract the relevant information from flake inputs
  registryData = writeText "registry-data.json" (
    lib.generators.toJSON { } {
      flakes = [
        {
          from = {
            id = "s"; # `_s_table`
            type = "indirect";
          };
          to = {
            inherit (inputs.nixpkgs-stable) lastModified narHash rev;
            path = inputs.nixpkgs-stable.outPath; # Maybe this will automagically copy?
            type = "path";
          };
          exact = true;
        }
      ];
      version = 2;
    }
  );

  buildCommand = ''
    mkdir -p $out/etc/nix
    cp $registryData $out/etc/nix/registry.json
  '';

  meta.description = "Nix registry with pinned nixpkgs versions for faster nix shell execution";
}
