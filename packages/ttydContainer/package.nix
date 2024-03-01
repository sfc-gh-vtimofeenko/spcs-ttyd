/* Produces container configurations to be consumed by the flake */
{ targetPkgs, self, ... }:
let
  pkgs = targetPkgs;

  fixUpEnv = pkgs.writeShellApplication {
    name = "fixup-env";
    runtimeInputs = [ pkgs.shadow ];

    meta.description = "Performs post-setup updates in the container allowing to use nix command.";

    text = ''
      mkdir -p /tmp

      ${pkgs.dockerTools.shadowSetup}
      groupadd -r nixbld
      for n in $(seq 1 10); do useradd -c "Nix build user $n" -d /var/empty -g nixbld -G nixbld -M -N -r -s "$(command -v nologin)" "nixbld$n"; done
    '';
  };

  nixConfig = pkgs.stdenv.mkDerivation {
    name = "nix-conf";
    src = ./.;
    dontUnpack = true;
    dontBuild = true;

    meta.description = "Sets nix up with required features";

    installPhase = ''
      mkdir -p $out/etc/nix
      cat <<EOF >$out/etc/nix/nix.conf
      experimental-features = nix-command flakes
      EOF
    '';
  };

  commonPackages = (builtins.attrValues
    {
      inherit (pkgs)
        coreutils-full
        nix
        bashInteractive# compared to standard bash this binds tab keys and has other QoL stuff. Needed for proper /bin/bash binary
        bash-completion# Shell experience is better
        vim-full# Some editor
        jq# Parsing JSON
        netcat# Allows bringing up servers
        curl# Curl
        ttyd# webshell
        inetutils# Telnet
        htop# Some monitoring
        gnugrep
        snowcli-2x
        snowsql
        toybox
        ;
    })
  ++ [ nixConfig fixUpEnv ];
in
pkgs.dockerTools.buildImage {
  name = "ttyd-container";
  tag = toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown");

  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    pathsToLink = [ "/bin" "/etc" "/var" ];
    paths = (builtins.attrValues {
      inherit (pkgs.dockerTools)
        usrBinEnv
        binSh
        caCertificates
        # fakeNss  # Not needed in a general root image, but might be needed for stuff like nginx
        ;
    }) ++ commonPackages;
  };

  /* runAsRoot needs nix with `kvm`. This can be achieved with cachix action:

    - uses: cachix/install-nix-action@vXX
      with:
        extra_nix_config: "system-features = nixos-test benchmark big-parallel kvm"

    which might need udevadm action:

    - name: Enable KVM group perms
        run: |
            echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
            sudo udevadm control --reload-rules
            sudo udevadm trigger --name-match=kvm

    source: https://github.blog/changelog/2023-02-23-hardware-accelerated-android-virtualization-on-actions-windows-and-linux-larger-hosted-runners/

    TODO: try with cachix and try with det sys action for the magic cache.
  */
  # runAsRoot = "";

  architecture = "amd64";

  config.Env = [
    "NIX_PAGER=cat"
    # A user is required by nix
    # https://github.com/NixOS/nix/blob/9348f9291e5d9e4ba3c4347ea1b235640f54fd79/src/libutil/util.cc#L478
    "USER=nobody"
    /* Allows using curl and other network utilities needing SSL. Provided by cacert above */
    "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
  ];
}
