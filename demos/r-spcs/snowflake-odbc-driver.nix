{ stdenv
, lib
, unixODBC
, openssl
, fetchurl
,
}:
let
  version = "3.5.0";
  sources = {
    "x86_64-linux" = {
      url = "https://sfc-repo.snowflakecomputing.com/odbc/linux/${version}/snowflake_linux_x8664_odbc-${version}.tgz";
      sha256 = "sha256-PaYX3Bgt4zqU9f1lUjYtDct685Fgk6LTQBi2K27j/lQ=";
    };
    "aarch64-linux" = {
      url = "https://sfc-repo.snowflakecomputing.com/odbc/linuxaarch64/${version}/snowflake_linux_aarch64_odbc-${version}.tgz";
      sha256 = "sha256-MORf5kY5b6059jsr4egPwBc0c3FXMEI8+p446EqY8fk=";
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
    cp -r ErrorMessages/en-US $out/lib
  '';

  postFixup = ''
    patchelf --set-rpath ${
      lib.makeLibraryPath [
        unixODBC
        openssl
        stdenv.cc.cc
      ]
    } \
      $out/lib/libSnowflake.so
  '';

  passthru = {
    fancyName = "SnowflakeDSIIDriver";
    driver = "lib/libSnowflake.so";
  };
}
