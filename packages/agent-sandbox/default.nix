{
  lib,
  stdenv,
  makeWrapper,
  bubblewrap,
  coreutils,
  procps,
  curl,
  gnugrep,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "agent-sandbox";
  version = "0.1.0";

  # Only the two scripts and the container config are install inputs. Keep
  # build artefacts (result, flake.lock) out of the source: with `src = ./.`
  # their appearance changes the output hash and drags every rebuild out of the
  # cache. (lib.sourceByRegex would do the same job, but it only matches
  # top-level entries, and the container config needs a subdirectory.)
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./sandbox.sh
      ./verify-sandbox.sh
      ./containers/storage.conf
      ./containers/containers.conf
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 sandbox.sh $out/bin/sandbox
    install -Dm755 verify-sandbox.sh $out/bin/sandbox-verify

    # podman/skopeo config the sandbox binds into the namespace. Kept out of
    # bin/ because these are data files, not programs; sandbox.sh finds them
    # through SANDBOX_CONTAINER_CONFIG_DIR (set by the wrapper below).
    install -Dm644 containers/storage.conf $out/share/agent-sandbox/containers/storage.conf
    install -Dm644 containers/containers.conf $out/share/agent-sandbox/containers/containers.conf

    # Rewrite '#!/usr/bin/env bash' to the store bash, and make bash a
    # runtime dependency. Without this the wrapped script cannot be exec'd:
    # /usr/bin/env does not exist on the NixOS host root.
    patchShebangs --host $out/bin

    runHook postInstall
  '';

  # bubblewrap is pinned to a store path, so the script never has to look it up.
  # SANDBOX_CONTAINER_CONFIG_DIR points at the installed container config, so the
  # sandbox does not depend on being run from a checkout.
  # coreutils/procps/curl/gnugrep are what the boundary checks in sandbox-verify run
  # on the host side (the grep package is named gnugrep, separate from coreutils).
  postFixup = ''
    wrapProgram $out/bin/sandbox \
      --set BWRAP ${lib.getExe bubblewrap} \
      --set SANDBOX_CONTAINER_CONFIG_DIR $out/share/agent-sandbox/containers \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          coreutils
        ]
      }

    wrapProgram $out/bin/sandbox-verify \
      --set SANDBOX_BIN $out/bin/sandbox \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          coreutils
          procps
          curl
          gnugrep
        ]
      }
  '';

  meta = with lib; {
    description = "Bubblewrap sandbox for coding agents: workspace-writable, rest-invisible";
    longDescription = ''
      Runs a command (pi, gemini, bash, …) in a bubblewrap namespace where the
      project directory, /tmp and ~/.pi are writable, the Nix store and system
      profiles are read-only, and everything else on the host is invisible.
      Threat model: accidental out-of-scope edits, not a malicious agent.
      Container image work is limited to import/tag/push (a rootless podman with
      a vfs store in the sandbox's /tmp); pulling, running and building images
      needs a subordinate uid range, which a bwrap user namespace cannot provide.
      sandbox-verify runs the boundary checks.
    '';
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "sandbox";
  };
})
