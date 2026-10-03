{
  lib,
  stdenv,        # overridden: cudaPackages.backendStdenv (the host compiler nvcc drives)
  cmake,
  ninja,
  pkg-config,
  fetchFromGitHub,
  cudaPackages,  # overridden: cudaPackages_13 (Blackwell sm_120 needs CUDA >= 13)
  python3,
}:

let
  version = "0.1.32";

  # The GPUs on the target host: RTX PRO 4000 Blackwell (24 GB) and RTX 5060
  # Ti (16 GB) - both sm_120.
  cudaArch = 120;

  src = fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    tag = "v${version}";
    hash = "sha256-HF941bwf8v/Fqxw6oYQnr5gEEO9Xq5Om8IfF3qQZpwE=";
  };

  # llama.cpp at the commit Strata pins (third_party/ggml/VERSION.txt).
  # Build-time: ggml (CPU experts, MMQ prompt kernels). Runtime: gguf-py
  # (imported by the model-prep tools). The vision build compiles llama.cpp's
  # mtmd encoder from the same checkout's top-level CMake project.
  llamaSrc = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash = "sha256-wHbXU0r6Dl0OwqDUJbEeeRwW894NcnIhrqBxzvFWooA=";
  };

  # The Python runtime: Strata's requirements.txt, plus jsonschema (optional
  # upstream; enables full json_schema validation). strata-init creates a
  # --system-site-packages venv on top of this, so setup.py pip-installs
  # nothing.
  strataPython = python3.withPackages (ps: with ps; [
    numpy
    jinja2
    regex
    pyyaml
    tqdm
    requests
    pillow
    psutil
    jsonschema
  ]);

  # Assembles a writable install from this package's read-only tree. It finds
  # $out/strata relative to itself at run time (referencing the derivation
  # from inside its own text would be circular).
  strataInit = lib.writeText {
    name = "strata-init";
    text = ''
      #!/bin/sh
      # Assemble a writable Strata install from the Nix package.
      #
      #   strata-init [--force] [dir]        (default dir: ~/Strata)
      #
      # Copies the read-only Strata tree (prebuilt engine, server, tools)
      # from the Nix store into a writable directory and creates the Python
      # environment. Model weights are NOT downloaded here: run setup.py
      # afterwards (a 70-120 GB download).
      set -eu

      self="$(readlink -f "$0")"
      out_dir="$(dirname "$(dirname "$self")")"
      tree="$out_dir/strata"
      python="${strataPython}/bin/python"

      force=0
      if [ "${1:-}" = "--force" ]; then
        force=1
        shift
      fi
      target="${1:-$HOME/Strata}"

      if [ -f "$target/engine/BUILD.json" ] && [ "$force" -eq 0 ]; then
        echo "A Strata install already exists at $target."
        echo
        echo "Set up / start a model with:"
        echo
        echo "  cd $target && .venv/bin/python setup.py --yes"
        exit 0
      fi

      if [ "$force" -eq 1 ] && [ -e "$target" ]; then
        echo "Removing existing $target (--force)"
        rm -rf "$target"
      fi

      echo "Assembling Strata in $target ..."
      mkdir -p "$target"
      cp -a "$tree/." "$target/"

      # Python environment for setup.py and the server. --system-site-packages
      # makes the Nix store's packages visible, so setup.py's pip step is a
      # no-op (the stamp written below records that).
      "$python" -m venv --system-site-packages "$target/.venv"

      "$target/.venv/bin/python" - "$target" <<'PY'
      import json
      import sys
      from pathlib import Path

      target = Path(sys.argv[1])
      # Bare names: setup.py's pip_install treats any requirement whose name
      # appears here (pinned or not) as already satisfied.
      names = [
          # Strata's requirements.txt
          "numpy", "jinja2", "regex", "pyyaml", "tqdm", "requests",
          "cmake", "ninja", "pillow", "psutil",
          "markupsafe", "certifi", "charset-normalizer", "idna",
          "urllib3", "colorama",
          # CUDA wheels setup.py would otherwise pip-install (~0.7 GB) for
          # any non-local engine; the Nix-built engine links the store's
          # CUDA libraries through its RPATH.
          "nvidia-cublas", "nvidia-cuda-runtime",
      ]
      stamp = target / ".venv" / ".strata-pip.json"
      stamp.write_text(json.dumps(sorted(names)))
      print("wrote", stamp)
      PY

      echo
      echo "Strata is installed in $target (engine: Nix-built, CUDA 13, sm_120, GPU vision)."
      echo
      echo "Next, download and prepare a model (70-120 GB):"
      echo
      echo "  cd $target"
      echo "  .venv/bin/python setup.py --yes"
      echo
      echo "then start it:"
      echo
      echo "  cd $target && ./run-<model>.sh"
    '';
  };
in
stdenv.mkDerivation {
  pname = "strata";
  inherit version;
  src = src;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    cudaPackages.cudatoolkit
  ];

  # find_package(CUDAToolkit) for the engine and the vision build.
  env.CUDAToolkit_ROOT = cudaPackages.cudatoolkit;

  cmakeFlags = [
    "-DSTRATA_ENABLE_CUDA=ON"
    "-DSTRATA_BUILD_TESTS=OFF"
    "-DCMAKE_CUDA_ARCHITECTURES=${toString cudaArch}"
    "-DSTRATA_GGML_DIR=${llamaSrc}"
  ];

  # The engine only (its static deps build with it). Tests are off: the
  # published tree's tests/ would fetch Catch2 from the network.
  cmakeBuildTarget = "strata";

  postBuild = ''
    # The image encoder is a separate CMake project (tools/vision) built
    # against llama.cpp's mtmd at the same pinned commit.
    cmake -S ${src}/tools/vision -B build-vision \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_DIR=${llamaSrc} \
      -DSTRATA_VISION_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES=${toString cudaArch}
    cmake --build build-vision --parallel "$NIX_BUILD_CORES" --target strata-vision
  '';

  installPhase = ''
    mkdir -p $out/bin

    # The runtime tree: what the user copies to a writable place
    # (strata-init) and runs setup.py in. setup.py writes configs, the venv,
    # model marks and run scripts into this tree.
    mkdir -p $out/strata
    cp -r ${src}/* $out/strata/

    # The prebuilt engine. setup.py accepts it via engine/BUILD.json
    # (source != "local", archs cover the GPUs, version >= MIN_ENGINE), so it
    # neither downloads nor compiles an engine at setup time.
    mkdir -p $out/strata/engine
    install -m755 build/strata $out/strata/engine/strata
    install -m755 build-vision/bin/strata-vision $out/strata/engine/strata-vision
    cat > $out/strata/engine/BUILD.json <<EOF
    {
      "source": "nix",
      "version": "${version}",
      "archs": [${toString cudaArch}],
      "ptx": false,
      "vision": "gpu",
      "vision_archs": [${toString cudaArch}],
      "cuda": "13.3",
      "cuda_dirs": ["${lib.getLib cudaPackages.cudatoolkit}"]
    }
    EOF

    # The pinned llama.cpp, trimmed to what setup.py's runtime tools need:
    # gguf-py (imported by iq_pack / mtp_pack / strata_pack) and ggml
    # (get_llama_cpp()'s existence check). This skips setup.py's 37 MB zip
    # download.
    mkdir -p $out/strata/third_party/llama.cpp
    cp -r ${llamaSrc}/ggml $out/strata/third_party/llama.cpp/ggml
    cp -r ${llamaSrc}/gguf-py $out/strata/third_party/llama.cpp/gguf-py

    # The launcher (finds $out/strata relative to itself at run time).
    install -m755 ${strataInit} $out/bin/strata-init

    # The exact interpreter the setup venv wraps.
    cat > $out/bin/strata-python <<EOF
    #!/bin/sh
    exec ${strataPython}/bin/python "\$@"
    EOF
    chmod +x $out/bin/strata-python
  '';

  doCheck = true;
  checkPhase = ''
    # No GPU is needed: this inspects the binaries and the interpreter only.
    # The engines must link the store's CUDA libraries (RPATH), and the
    # Python environment must import everything the server and the tools use.
    readelf -d build/strata | grep -q "libcudart.so.13"
    readelf -d build/strata | grep -Eq "RPATH|RUNPATH"
    readelf -d build-vision/bin/strata-vision | grep -q "libcudart.so.13"
    ${strataPython}/bin/python -c "import numpy, jinja2, regex, yaml, tqdm, requests, PIL, psutil, jsonschema"
  '';

  meta = with lib; {
    description = "Fast MoE inference engine for Qwen3.8-Flash-Next on NVIDIA RTX 40/50 series GPUs";
    longDescription = ''
      Strata runs Qwen3.8-Flash-Next (a ~30B MoE model) at high throughput on a
      consumer NVIDIA GPU. This package builds the CUDA engine (C++/CUDA, sm_120)
      and the GPU image encoder, and ships the Python server and the model-prep
      tools. `strata-init` assembles a writable install (default: ~/Strata) with
      the prebuilt engine and the Python environment; `setup.py` then downloads
      and prepares the model (70-120 GB, not part of the package).
    '';
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "strata-init";
  };
}
