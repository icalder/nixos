# Windows Helper Scripts for llama.cpp

## Background

This is a WSL Linux system. Windows is running llama-swap and llama.cpp.  This directory exists to provide helper scripts for managing llama.cpp installations and upgrades.

## Where are the files

### llama.cpp

`~/winhome/llama-cpp/`

Note: `~/winhome` is a symlink to `/mnt/c/Users/iainc/`.

### models

`/mnt/f/llama-models/`

### llama-swap config

`~/winhome/scoop/persist/llama-swap/config.yaml`

## Where do we get llama.cpp binaries

From [github releases](https://github.com/ggml-org/llama.cpp/releases).  Use `gh`.
We download the zip files for "Windows x64 (CUDA 13)" and "CUDA 13.4 DLLs" (also x64).

Note: each build is its own release tagged `b<number>` (e.g. `b11371`) containing
the full asset set.  Version releases like `v0.5.0` only contain `nightly-tag.txt`
and no binaries, so "latest" always means the newest `b####` release.

## Scripts

### update-llama-cpp.sh

Updates the Windows llama.cpp install (`~/winhome/llama-cpp/`) from a release.

```sh
nix develop                 # devshell with unzip, gh, curl, ...
./update-llama-cpp.sh                  # update to the latest build release
./update-llama-cpp.sh b11371           # update to a specific build ("11371" works too)
./update-llama-cpp.sh --dry-run        # preview the plan, change nothing
nix run . -- b11371                    # same, without entering the devshell
```

- Downloads `llama-b<N>-bin-win-cuda-13.x-x64.zip` and `cudart-llama-bin-win-cuda-13.x-x64.zip`
  from the `b<N>` release, verifies each zip, and extracts over the existing install.
- Deletes stale files no longer shipped by the release.  The managed file set is tracked
  in `~/winhome/llama-cpp/.llama-cpp-manifest`; any other file in the directory is never
  touched.  On a first run with no manifest, the baseline is taken from installer zips
  still present in the install dir, or from the directory contents if none are present.
- Installer zips are never kept in the install directory; downloaded zips are cached in
  `~/.cache/llama-cpp-update` (override with `--cache-dir`) so a dry run, retry, or second
  run does not re-download.  Cache entries for other builds are pruned automatically.
- Stop llama-swap (and anything else using these binaries) on Windows before running:
  in-use files cannot be overwritten.  If extraction fails midway, the manifest is left
  untouched, so the next run self-heals.