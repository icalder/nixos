#!/usr/bin/env bash
#
# update-llama-cpp.sh - update the Windows llama.cpp install from a GitHub release.
#
# Downloads the "Windows x64 (CUDA 13)" binaries zip and the "CUDA 13.x DLLs"
# zip for a given build (or the latest build release), extracts them over the
# existing install, removes stale files no longer shipped, and deletes any
# installer zips left in the install directory.

set -euo pipefail

REPO="ggml-org/llama.cpp"
CUDA_MAJOR="13"
MANIFEST_NAME=".llama-cpp-manifest"
DEFAULT_TARGET="$HOME/winhome/llama-cpp"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/llama-cpp-update"

BUILD=""
TARGET="$DEFAULT_TARGET"
DRY_RUN=0
workdir=""

log() { printf '[update-llama-cpp] %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

usage() {
  cat <<'EOF'
Update the Windows llama.cpp install from a llama.cpp GitHub release.

Downloads the "Windows x64 (CUDA 13)" binaries zip and the "CUDA 13.x DLLs"
zip for the given build (or the latest build release), extracts them over the
existing install (overwriting files), removes stale files that the release no
longer ships, and deletes installer zips from the install directory.

Usage: update-llama-cpp.sh [BUILD] [options]

  BUILD            build tag, e.g. b11371 (leading "b" optional)
                   default: the latest build release

Options:
  --target DIR     install directory (default: ~/winhome/llama-cpp)
  --cache-dir DIR  where downloaded zips are kept between runs, so a
                   dry-run/real run or retry does not re-download
                   (default: $XDG_CACHE_HOME/llama-cpp-update)
  --dry-run        show what would change, change nothing
  -h, --help       show this help

Installed files are tracked in <target>/.llama-cpp-manifest; files that are
not part of a managed install are never touched. Stop llama-swap on Windows
before updating, as files in use cannot be overwritten.
EOF
}

cleanup() {
  if [[ -n "$workdir" && -d "$workdir" ]]; then
    rm -rf -- "$workdir"
  fi
}
trap cleanup EXIT

parse_args() {
  TARGET="$DEFAULT_TARGET"
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --target)
        if (( $# < 2 )); then die "--target requires a directory"; fi
        TARGET="$2"
        shift
        ;;
      --target=*)
        TARGET="${1#*=}"
        ;;
      --cache-dir)
        if (( $# < 2 )); then die "--cache-dir requires a directory"; fi
        CACHE_DIR="$2"
        shift
        ;;
      --cache-dir=*)
        CACHE_DIR="${1#*=}"
        ;;
      --)
        shift
        if (( $# > 1 )); then die "at most one BUILD argument"; fi
        if (( $# == 1 )) && [[ -n "$1" ]]; then BUILD="$1"; fi
        break
        ;;
      -*)
        die "unknown option: $1 (see --help)"
        ;;
      *)
        if [[ -n "$BUILD" ]]; then die "at most one BUILD argument (got '$BUILD' and '$1')"; fi
        BUILD="$1"
        ;;
    esac
    shift
  done
  if [[ -z "${TARGET//\//}" ]]; then die "--target must not be empty"; fi
}

# Print the build tag to install: $1 if given, else the newest b#### release.
resolve_build() {
  local requested="${1:-}" tag t
  if [[ -n "$requested" ]]; then
    if [[ ! "$requested" =~ ^b?[0-9]+$ ]]; then
      die "invalid build '$requested' (expected e.g. b11371 or 11371)"
    fi
    tag="b${requested#b}"
    if ! gh api "repos/$REPO/releases/tags/$tag" --jq '.tag_name' >/dev/null 2>&1; then
      die "release $tag not found in $REPO"
    fi
    printf '%s\n' "$tag"
    return 0
  fi
  while IFS= read -r t; do
    if [[ "$t" =~ ^b[0-9]+$ ]]; then
      printf '%s\n' "$t"
      return 0
    fi
  done < <(gh api "repos/$REPO/releases?per_page=20" --jq '.[].tag_name')
  die "no build release (b####) found among the 20 most recent releases of $REPO"
}

# Print the asset table (name<TAB>browser_download_url) of release $1.
fetch_release_assets() {
  gh api "repos/$REPO/releases/tags/$1" \
    --jq '.assets[] | [.name, .browser_download_url] | @tsv'
}

# From an asset table, print the line (name<TAB>url) of the highest-version
# asset whose line matches ERE $2. Prints nothing if there is no match.
pick_asset() {
  { grep -E "$2" <<<"$1" || true; } | sort -V | tail -n 1
}

# Download $1 to the cache as $2 unless a valid copy is already cached.
# Prints the path of the usable zip.
fetch_zip() {
  local url="$1" name="$2" dest
  mkdir -p -- "$CACHE_DIR"
  dest="$CACHE_DIR/$name"
  if [[ -s "$dest" ]] && unzip -tq "$dest" >/dev/null 2>&1; then
    log "using cached $name"
  else
    log "downloading $name"
    if ! curl -fL --retry 3 --retry-connrefused --progress-bar -o "$dest.part" "$url"; then
      rm -f -- "$dest.part"
      die "download failed: $url"
    fi
    mv -f -- "$dest.part" "$dest"
  fi
  printf '%s\n' "$dest"
}

# Delete cached zips not listed in the space-separated $1.
prune_cache() {
  local keep=" $1 " z name
  for z in "$CACHE_DIR"/*.zip; do
    if [[ ! -e "$z" ]]; then continue; fi
    name=$(basename -- "$z")
    if [[ "$keep" != *" $name "* ]]; then
      rm -f -- "$z"
    fi
  done
}

# Print the file names contained in zip $1, one per line.
zip_file_list() {
  unzip -Z1 "$1"
}

manifest_path() {
  printf '%s\n' "$TARGET/$MANIFEST_NAME"
}

# Print the files tracked in the current manifest (sorted). Empty if none.
load_manifest() {
  local f
  f=$(manifest_path)
  if [[ ! -f "$f" ]]; then return 0; fi
  { grep -vE '^[[:space:]]*(#|$)' -- "$f" || true; } | sort -u
}

# Print the build recorded in the current manifest. Empty if none.
manifest_build() {
  local f
  f=$(manifest_path)
  if [[ ! -f "$f" ]]; then return 0; fi
  { grep -m 1 -E '^# build: ' -- "$f" || true; } | cut -d ' ' -f 3-
}

# Read a file list on stdin and write it as the manifest for build $1.
save_manifest() {
  local tag="$1" f
  f=$(manifest_path)
  {
    echo "# llama.cpp install manifest - managed by update-llama-cpp.sh, do not edit"
    echo "# build: $tag"
    echo "# updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sort -u
  } > "$f"
}

# Print the installer zips (by name) left in the install directory.
installer_zip_pattern() {
  find "$TARGET" -maxdepth 1 -type f \
    \( -name 'llama-b[0-9]*-bin-win-*.zip' -o -name 'cudart-llama-bin-win-*.zip' \) \
    -printf '%f\n'
}

# Print the baseline file set: the files of the previous managed install.
# Source, in order of preference:
#   1. the manifest, if present
#   2. installer zips left in the install directory
#   3. every regular file in the install directory (zips and manifest excluded)
load_baseline() {
  local f zips=() z
  f=$(manifest_path)
  if [[ -f "$f" ]]; then
    load_manifest
    return 0
  fi
  while IFS= read -r z; do
    zips+=("$TARGET/$z")
  done < <(installer_zip_pattern)
  if (( ${#zips[@]} > 0 )); then
    log "no manifest found; baselining on installer zips present in $TARGET"
    for z in "${zips[@]}"; do zip_file_list "$z"; done | sort -u
    return 0
  fi
  log "no manifest or installer zips found; baselining on all files in $TARGET"
  ( cd "$TARGET" && find . -maxdepth 1 -type f ! -name '*.zip' \
      ! -name "$MANIFEST_NAME" -printf '%f\n' ) | sort -u
}

main() {
  parse_args "$@"

  local missing=()
  command -v gh >/dev/null || missing+=("gh")
  command -v curl >/dev/null || missing+=("curl")
  command -v unzip >/dev/null || missing+=("unzip")
  if (( ${#missing[@]} > 0 )); then
    die "missing tool(s): ${missing[*]} - enter the devshell first (nix develop)"
  fi
  if [[ ! -d "$TARGET" ]]; then
    die "install directory not found: $TARGET"
  fi

  local tag
  tag=$(resolve_build "$BUILD")
  log "build: $tag"

  local assets
  if ! assets=$(fetch_release_assets "$tag"); then
    die "could not fetch release $tag from $REPO"
  fi

  local TAB=$'\t'
  local bin_line cuda_line bin_name cuda_name bin_url cuda_url
  bin_line=$(pick_asset "$assets" "^llama-${tag}-bin-win-cuda-${CUDA_MAJOR}\.[0-9]+-x64\.zip${TAB}")
  cuda_line=$(pick_asset "$assets" "^cudart-llama-bin-win-cuda-${CUDA_MAJOR}\.[0-9]+-x64\.zip${TAB}")
  if [[ -z "$bin_line" ]]; then
    die "release $tag has no Windows x64 CUDA ${CUDA_MAJOR}.x binaries zip"
  fi
  if [[ -z "$cuda_line" ]]; then
    die "release $tag has no CUDA ${CUDA_MAJOR}.x x64 DLLs zip"
  fi
  bin_name=${bin_line%%"$TAB"*};  bin_url=${bin_line#*"$TAB"}
  cuda_name=${cuda_line%%"$TAB"*}; cuda_url=${cuda_line#*"$TAB"}

  local bin_zip cuda_zip
  bin_zip=$(fetch_zip "$bin_url" "$bin_name")
  cuda_zip=$(fetch_zip "$cuda_url" "$cuda_name")
  prune_cache "$bin_name $cuda_name"

  workdir=$(mktemp -d)
  local new_list="$workdir/new.txt" base_list="$workdir/base.txt"
  local stale_list="$workdir/stale.txt" old_zips="$workdir/old-zips.txt"

  { zip_file_list "$bin_zip"; zip_file_list "$cuda_zip"; } | sort -u > "$new_list"
  load_baseline > "$base_list"
  comm -23 -- "$base_list" "$new_list" > "$stale_list"
  installer_zip_pattern > "$old_zips"

  local old_build n_new n_stale n_zips f z
  old_build=$(manifest_build)
  n_new=$(wc -l < "$new_list")
  n_stale=$(wc -l < "$stale_list")
  n_zips=$(wc -l < "$old_zips")

  echo
  echo "llama.cpp update plan"
  echo "  install dir : $TARGET"
  echo "  build       : ${old_build:-<unmanaged>} -> $tag"
  echo "  zips        : $bin_name, $cuda_name"
  echo "  files       : $n_new (existing files overwritten in place)"
  echo "  remove      : $n_stale stale file(s)"
  while IFS= read -r f; do printf '    - %s\n' "$f"; done < "$stale_list"
  if (( n_zips > 0 )); then
    echo "  zips in dir : $n_zips installer zip(s) to delete"
    while IFS= read -r z; do printf '    - %s\n' "$z"; done < "$old_zips"
  fi

  if (( DRY_RUN )); then
    log "dry run - no changes made"
    return 0
  fi

  # Remove stale managed files, then install, then tidy up zips.
  while IFS= read -r f; do
    if [[ -f "$TARGET/$f" ]]; then rm -f -- "$TARGET/$f"; fi
  done < "$stale_list"

  if ! unzip -oq "$bin_zip" -d "$TARGET"; then die "failed to extract $bin_name"; fi
  if ! unzip -oq "$cuda_zip" -d "$TARGET"; then die "failed to extract $cuda_name"; fi

  while IFS= read -r z; do
    if [[ -n "$z" ]]; then rm -f -- "$TARGET/$z"; fi
  done < "$old_zips"

  save_manifest "$tag" < "$new_list"
  log "done: $TARGET is now on $tag"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
