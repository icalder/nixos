{
  lib,
  stdenv,
  makeWrapper,
  bubblewrap,
  coreutils,
  procps,
  curl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "agent-sandbox";
  version = "0.1.0";

  # Only the two scripts are install inputs. Keep build artefacts (result,
  # flake.lock) out of the source: with `src = ./.` their appearance changes
  # the output hash and drags every rebuild out of the cache.
  src = lib.sourceByRegex ./. [ "sandbox\.sh" "verify-sandbox\.sh" ];

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 sandbox.sh $out/bin/sandbox
    install -Dm755 verify-sandbox.sh $out/bin/sandbox-verify

    # Rewrite '#!/usr/bin/env bash' to the store bash, and make bash a
    # runtime dependency. Without this the wrapped script cannot be exec'd:
    # /usr/bin/env does not exist on the NixOS host root.
    patchShebangs --host $out/bin

    runHook postInstall
  '';

  # bubblewrap is pinned to a store path, so the script never has to look it up.
  # coreutils/procps/curl are what the boundary checks in sandbox-verify run.
  postFixup = ''
    wrapProgram $out/bin/sandbox \
      --set BWRAP ${lib.getExe bubblewrap} \
      --prefix PATH : ${lib.makeBinPath [ bubblewrap coreutils ]}

    wrapProgram $out/bin/sandbox-verify \
      --set SANDBOX_BIN $out/bin/sandbox \
      --prefix PATH : ${lib.makeBinPath [ bubblewrap coreutils procps curl ]}
  '';

  meta = with lib; {
    description = "Bubblewrap sandbox for coding agents: workspace-writable, rest-invisible";
    longDescription = ''
      Runs a command (pi, gemini, bash, …) in a bubblewrap namespace where the
      project directory, /tmp and ~/.pi are writable, the Nix store and system
      profiles are read-only, and everything else on the host is invisible.
      Threat model: accidental out-of-scope edits, not a malicious agent.
      sandbox-verify runs the boundary checks.
    '';
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "sandbox";
  };
})
