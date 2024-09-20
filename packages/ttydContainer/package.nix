/* Produces container configurations to be consumed by the flake */
{ targetPkgs, self, ... }:
let
  pkgs = targetPkgs;

  snowflakeODBC = self.packages.${pkgs.system}.snowflake-odbc;

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

  createODBCini = pkgs.writeShellApplication {
    name = "create-odbc-ini";

    runtimeInputs = [ pkgs.coreutils-full ];

    text = ''
      cat <<EOF >/etc/odbc.ini
      [ODBC Data Sources]
      snowodbc = SnowflakeDSIIDriver

      [snowodbc]
      Driver      = ${snowflakeODBC}/lib/libSnowflake.so
      Description =
      server      = $SNOWFLAKE_HOST
      role        = PUBLIC
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
        moreutils
        caddy
        unixODBC

        ;
    })
  ++ [
    nixConfig
    createODBCini
  ];
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

  # Needs Nix runner with kvm capabilities. GH actions provide one.
  runAsRoot = ''
    mkdir -p /tmp

    ${pkgs.dockerTools.shadowSetup}
    groupadd -r nixbld
    for n in $(seq 1 10); do useradd -c "Nix build user $n" -d /var/empty -g nixbld -G nixbld -M -N -r -s "$(command -v nologin)" "nixbld$n"; done

    # environment.etc
    cat <<EOF >/etc/odbcinst.ini
    [ODBC Drivers]
    SnowflakeDSIIDriver=Installed

    [SnowflakeDSIIDriver]
    APILevel=1
    ConnectFunctions=YYY
    Description=Snowflake DSII
    Driver=${snowflakeODBC}/lib/libSnowflake.so
    DriverODBCVer=03.52
    SQLLevel=1
    EOF
  '';

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
