{ fetchurl
, stdenv
,
}:
let
  version = "3.4.1";
  sources = {
    "x86_64-linux" = {
      url = "https://sfc-repo.snowflakecomputing.com/odbc/linux/${version}/snowflake_linux_x8664_odbc-${version}.tgz";
      sha256 = "sha256-q4MECeJUews68RWdAufgdt0+hPyB8QZ5GQqhJCgDQJQ=";
    };
    "aarch64-linux" = {
      url = "https://sfc-repo.snowflakecomputing.com/odbc/linuxaarch64/${version}/snowflake_linux_aarch64_odbc-${version}.tgz";
      sha256 = "sha256-5Iui4KrsP1U/ZtUyWEOKbm0Gyg8B377VMzhLby2LDpY=";
    };
  };
in
stdenv.mkDerivation {
  pname = "snowflake-odbc-driver";
  inherit version;
  src = fetchurl sources.${stdenv.hostPlatform.system};

  # Basically use precompiled so
  installPhase = ''
    mkdir -p $out/lib
    cp -r lib/* $out/lib
  '';
}

