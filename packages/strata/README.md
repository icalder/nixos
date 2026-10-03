# Strata (Nix package)

Packages [Strata](https://github.com/Niko1221/Strata) — a fast MoE inference
engine for Qwen3.8-Flash-Next on NVIDIA RTX 40/50 series GPUs.

The package builds the CUDA engine (`strata`) and the GPU image encoder
(`strata-vision`) from source with the Nix CUDA 13 toolchain, and ships the
Python server, the model-prep tools, and the pinned llama.cpp sources they
need. Model weights are **not** part of the package.

## What's in the store

| Path | What it is |
| --- | --- |
| `bin/strata-init` | Assembles a writable install (default: `~/Strata`) from the read-only store tree, including the Python environment |
| `bin/strata-python` | The exact Python 3.14 interpreter the setup venv wraps (all dependencies preinstalled) |
| `strata/` | The runtime tree: `serve/`, `tools/`, `setup.py`, ... |
| `strata/engine/strata` | The prebuilt CUDA engine (sm_120, CUDA 13.3) |
| `strata/engine/strata-vision` | The GPU image encoder |
| `strata/engine/BUILD.json` | Marks the engine as a Nix-built, ready-made engine, so `setup.py` uses it as-is |
| `strata/third_party/llama.cpp/` | The pinned llama.cpp commit, trimmed to `ggml/` + `gguf-py/` (skips setup.py's 37 MB download) |

## Usage

```sh
# 1. Assemble the install (one-time, a few seconds)
strata-init

# 2. Download + prepare a model (70-120 GB), then it starts
cd ~/Strata
.venv/bin/python setup.py --yes

# 3. Start a configured model later
cd ~/Strata && ./run-<model>.sh
```

`strata-init --force [dir]` reassembles from scratch into `dir`.

## Why the indirection

The Nix store is read-only, but `setup.py` writes into its tree (config,
venv, model marks, run scripts). So `strata-init` copies the store tree into
a writable directory first, then creates the `.venv` on top of the
Nix-managed Python (`--system-site-packages`, nothing to pip-install).

`setup.py` is otherwise left to do exactly what it does upstream:

- **Engine** — `engine/BUILD.json` says `source: "nix"`, archs `[120]`,
  version `0.1.32` (= `MIN_ENGINE`). `get_prebuilt` therefore accepts the
  engine as-is: no download, no compile.
- **Python packages** — `.venv/.strata-pip.json` is pre-populated with every
  requirement name, so `setup.py`'s pip step (including ~0.7 GB of NVIDIA
  CUDA wheels that the Nix-built engine doesn't need — it links the store's
  CUDA libraries through its RPATH) is a no-op.
- **llama.cpp** — `third_party/llama.cpp` already has `ggml/` and
  `gguf-py/`, so `get_llama_cpp()` finds it and skips the zip download.
- **Model files** — still downloaded by `setup.py` into the sibling
  `Strata-data/` folder (70-120 GB). That's data, not a package.

## Build notes

- **CUDA** — `cudaPackages_13` (13.3) from nixpkgs-unstable; sm_120
  (Blackwell) requires CUDA >= 13. Built with
  `cudaPackages_13.backendStdenv` (GCC 15.3) and
  `CUDAToolkit_ROOT=<cudatoolkit>`, the same recipe the llama.cpp WSL setup
  uses.
- **Archs** — `120` only, for the host GPUs (RTX PRO 4000 Blackwell,
  RTX 5060 Ti). Change `cudaArch` in `strata.nix` and rebuild for other
  cards (the engine refuses compute capability < 7.5).
- **llama.cpp** — pinned commit `3cf03257` (Strata's
  `third_party/ggml/VERSION.txt`), fetched directly (no network in the
  build). The engine takes ggml from it (`STRATA_GGML_DIR`); the vision
  build compiles llama.cpp's `mtmd` encoder from the same checkout.
- **Python** — nixpkgs-unstable Python 3.14 with the `requirements.txt`
  dependencies plus `jsonschema` (optional upstream; enables full
  `json_schema` validation).
- **WSL** — the engine dlopen's `libcuda.so.1` from the Windows driver at
  runtime; the host's `LD_LIBRARY_PATH=/usr/lib/wsl/lib` covers that, same
  as `llama-cpp-cuda`.

## Maintenance

- Bumping Strata: update `version` + the tarball `hash` in `strata.nix`
  (and the pinned llama.cpp rev if `third_party/ggml/VERSION.txt` moved).
  `setup.py`'s `MIN_ENGINE` must stay <= the package version.
- The engine is rebuilt from source by Nix; `setup.py --build` (compiling in
  the tree) is out of scope for this package.
