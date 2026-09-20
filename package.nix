{ lib
, stdenvNoCC
, makeWrapper
, gawk
, ncdu
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "zfs-ncdu";
  version = "0.1.0";

  src = builtins.path {
    path = ./.;
    name = "zfs-ncdu-source";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./tests/run.sh ${gawk}/bin/awk
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    make install PREFIX="$out"
    # zfs itself is deliberately left to the host: the pools belong to the
    # running system, not to the closure.
    wrapProgram "$out/bin/zfs-ncdu" \
      --prefix PATH : ${lib.makeBinPath [ gawk ncdu ]}
    runHook postInstall
  '';

  meta = {
    description = "Browse ZFS space accounting in ncdu";
    longDescription = ''
      Renders ZFS dataset, snapshot and reservation accounting into ncdu's own
      JSON export format and opens it with the real ncdu binary, showing space
      that walking a directory tree cannot see.
    '';
    homepage = "https://github.com/Spaceghost/zfs-ncdu";
    license = lib.licenses.mit;
    mainProgram = "zfs-ncdu";
    platforms = lib.platforms.unix;
  };
})
