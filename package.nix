{ lib
, stdenv
, fetchurl
, makeBinaryWrapper
, unzip
, ripgrep
, sysctl
, writableTmpDirAsHomeHook
}:

let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  assets = builtins.fromJSON (builtins.readFile ./platforms.json);
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
    # Keep upgrades managed by Nix rather than OpenCode's self-updater.
    # ripgrep on PATH prevents a runtime download; macOS also needs sysctl.
    ${if stdenv.hostPlatform.isLinux then ''
      # Upstream's Linux assets are dynamically linked. Invoke glibc's loader
      # directly because patchelf breaks the embedded Bun payload.
      makeBinaryWrapper ${stdenv.cc.bintools.dynamicLinker} "$out/bin/opencode" \
        --add-flags "--library-path ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}" \
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
    # Defined in packages/core/src/flag/flag.ts in upstream v1.18.33.
    # Keep the install check from fetching the model catalog.
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
