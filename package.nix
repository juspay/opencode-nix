{ lib
, stdenv
, fetchurl
, makeBinaryWrapper
, unzip
, ripgrep
, sysctl
, pkgsMusl
, writableTmpDirAsHomeHook
}:

let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  assets = {
    x86_64-linux = "opencode-linux-x64-musl.tar.gz";
    aarch64-linux = "opencode-linux-arm64-musl.tar.gz";
    aarch64-darwin = "opencode-darwin-arm64.zip";
    x86_64-darwin = "opencode-darwin-x64.zip";
  };
  system = stdenv.hostPlatform.system;
  asset = assets.${system} or (throw "Unsupported OpenCode platform: ${system}");
in
stdenv.mkDerivation {
  pname = "opencode";
  inherit (sources) version;

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${sources.version}/${asset}";
    hash = sources.hashes.${system};
  };

  sourceRoot = ".";
  nativeBuildInputs = [ makeBinaryWrapper ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ unzip ];
  dontConfigure = true;
  dontBuild = true;
  # Both operations can corrupt the embedded Bun executable payload.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode "$out/libexec/opencode"
    mkdir -p "$out/bin"
    ${if stdenv.hostPlatform.isLinux then ''
      # Upstream's musl assets are dynamically linked. Invoke the loader directly
      # to preserve the Bun payload and avoid a non-NixOS /lib interpreter path.
      makeBinaryWrapper ${pkgsMusl.musl}/lib/ld-musl-${stdenv.hostPlatform.parsed.cpu.name}.so.1 "$out/bin/opencode" \
        --add-flags "--library-path ${lib.makeLibraryPath [ pkgsMusl.stdenv.cc.cc.lib pkgsMusl.stdenv.cc.cc.libgcc ]}" \
        --add-flags "$out/libexec/opencode" \
    '' else ''
      makeBinaryWrapper "$out/libexec/opencode" "$out/bin/opencode" \
    ''} \
      --prefix PATH : ${lib.makeBinPath ([ ripgrep ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ sysctl ])} \
      --set OPENCODE_DISABLE_AUTOUPDATE true
    runHook postInstall
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  nativeInstallCheckInputs = [ writableTmpDirAsHomeHook ];
  installCheckPhase = ''
    runHook preInstallCheck
    export XDG_CACHE_HOME=$(mktemp -d)
    export XDG_DATA_HOME=$(mktemp -d)
    export XDG_CONFIG_HOME=$(mktemp -d)
    export OPENCODE_DISABLE_MODELS_FETCH=true
    # Bun extracts native modules under TMPDIR/opencode; the unpacked executable
    # already occupies that name in Nix's default build directory.
    actual=$(TMPDIR="$(mktemp -d)" "$out/bin/opencode" --version)
    echo "OpenCode version: $actual"
    test "$actual" = "${sources.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "AI coding agent built for the terminal";
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases/tag/v${sources.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames assets;
    mainProgram = "opencode";
  };
}
