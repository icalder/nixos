# CMake Strategy: FetchContent vs find_package

This document explains why we replace the upstream `CMakeLists.txt` with a custom version for the Nix build.

## The Problem: FetchContent

The upstream `SectorFlux` project uses `FetchContent` to manage dependencies. 

*   **What it does:** It downloads source code from the internet (usually GitHub) *during* the CMake configuration step. It then compiles that dependency as part of the project.
*   **Why upstream uses it:** It provides "Developer Convenience". Anyone who clones the repo can run `cmake .. && make` without needing to manually install libraries like `crow` or `asio` first.
*   **Why it fails in Nix:** Nix builds run in a **strict sandbox** with **no internet access**. When `FetchContent` tries to `git clone` from GitHub, it hits a network wall and fails.

## The Solution: find_package

Our custom `CMakeLists.txt` uses `find_package` (and `find_path` for header-only libraries) instead.

*   **What it does:** It looks for libraries that are **already installed** on the system. It does not download anything. It expects headers to be in include paths and binaries in library paths.
*   **Where does it look?** It searches standard directories, most importantly those specified in `CMAKE_PREFIX_PATH`.

### How Nix makes `find_package` work

When we add libraries to `buildInputs` in `flake.nix`:

```nix
buildInputs = [ pkgs.asio pkgs.crow ... ];
```

Nix automatically populates the `CMAKE_PREFIX_PATH` environment variable inside the build sandbox.

1.  Nix installs `asio` to `/nix/store/HASH-asio-1.30.2`.
2.  Nix adds `/nix/store/HASH-asio-1.30.2` to `CMAKE_PREFIX_PATH`.
3.  Our `CMakeLists.txt` runs `find_package(asio)` (or `find_path`).
4.  CMake looks at `CMAKE_PREFIX_PATH`, finds the library files, and successfully links them.

## Summary

We changed the build strategy from:
> "Download these libraries from GitHub and compile them." (`FetchContent`)

To:
> "Look for these libraries in the locations provided by the environment." (`find_package`)

This ensures the build is **hermetic**, **reproducible**, and works within the Nix sandbox.
