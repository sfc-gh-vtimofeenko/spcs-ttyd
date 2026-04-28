# Cortex Code CLI – pre-built Bun SEA, packaged for Nix.
# Run `nix run .#update-cortex` to update to the latest stable release.
{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  python312,
  zlib,
}:
let
  version = "1.0.66+185850.47d3f3ed24e7";

  # '+' must be percent-encoded in the S3 path; construct it once.
  ev = lib.replaceStrings [ "+" ] [ "%2B" ] version;
  base = "https://sfc-repo.snowflakecomputing.com/cortex-code-cli/a4643c4278/${ev}";

  sources = {
    "x86_64-linux" = {
      url = "${base}/coco-${ev}-linux-amd64.tar.gz";
      sha256 = "sha256-pUYmzpqAao56+PSH/cWvBWpmTLo0YZFx5LEZsEhDAzA=";
    };
    "aarch64-linux" = {
      url = "${base}/coco-${ev}-linux-arm64.tar.gz";
      sha256 = "sha256-veZeQK1ly63lAa4wNLkU9DY6we+1JRMFjYvjNgUsZ7c=";
    };
    "x86_64-darwin" = {
      url = "${base}/coco-${ev}-darwin-amd64.tar.gz";
      sha256 = "sha256-7UOuRnzFn9we/3cWvTdGN4fSYzaTyNRXWdW6dn8nNDA=";
    };
    "aarch64-darwin" = {
      url = "${base}/coco-${ev}-darwin-arm64.tar.gz";
      sha256 = "sha256-Auu0Vqt3744tw4R5xu+QDH3RqYkfNfkKtEBysjXEIDM=";
    };
  };
in
stdenv.mkDerivation {
  pname = "cortex";
  inherit version;

  src = fetchurl sources.${stdenv.hostPlatform.system};

  # Stay in the build dir; the tarball extracts to a versioned subdirectory
  # whose name we discover at runtime rather than hard-coding.
  sourceRoot = ".";

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  # Provide common dynamic libraries for the bundled Linux ELF extensions.
  # Add more here if autoPatchelfHook reports unresolved dependencies.
  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib # libstdc++.so.6
    zlib
    python312 # runtime interpreter for the bundled reladiff-venv
  ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    extracted=$(find . -maxdepth 1 -mindepth 1 -type d | head -1)
    mkdir -p "$out/share/cortex" "$out/bin"
    cp -r "$extracted"/. "$out/share/cortex/"

    # The bundled reladiff-venv ships without a python3.12 binary; its
    # bin/python and bin/python3 symlinks point to it and trip the
    # noBrokenSymlinks check.  Provide it before fixupPhase runs.
    if [ -d "$out/share/cortex/reladiff-venv/bin" ]; then
      ln -sf ${python312}/bin/python3.12 \
        "$out/share/cortex/reladiff-venv/bin/python3.12"
      cfg="$out/share/cortex/reladiff-venv/pyvenv.cfg"
      [ -f "$cfg" ] && sed -i \
        "s|^home = .*|home = ${python312}/bin|" "$cfg"
    fi

    if [ -f "$out/share/cortex/dist/index.js" ]; then
      # Bun runtime shipped separately from its entry point.
      makeWrapper "$out/share/cortex/cortex" "$out/bin/cortex" \
        --add-flags "$out/share/cortex/dist/index.js"
    else
      # Bun SEA: the binary resolves sibling assets (node_modules/,
      # bundled_web/, …) via /proc/self/exe (Linux) or
      # _NSGetExecutablePath (macOS).  A symlink lets the OS resolve
      # that path back to $out/share/cortex/ where the assets live.
      ln -sf "$out/share/cortex/cortex" "$out/bin/cortex"
    fi

    runHook postInstall
  '';

  meta = {
    description = "Snowflake's AI-powered coding assistant CLI";
    license = lib.licenses.unfreeRedistributable;
    maintainers = [ ];
    platforms = builtins.attrNames sources;
    mainProgram = "cortex";
  };
}
