#!/usr/bin/env bash
set -euo pipefail

# llama-audit.sh
# Compare a llama.cpp tag (or a Nix config) to the latest published release
# and produce a performance-focused summary using gh + jq.
# Enhanced: can read a llama-swap-settings.nix to prioritize commits
# that match the exact flags and parameters you use.

usage() {
  cat <<EOF
Usage: $0 [--config PATH] [--tag TAG] [--repo OWNER/REPO] [--swap-settings PATH] [--target TAG] [--brief]

Options:
  --config PATH       Parse a Nix configuration to extract a tag/version (e.g. configuration.nix)
  --tag TAG           Use explicit Git tag (e.g. b9222)
  --repo REPO         GitHub repo (default: ggml-org/llama.cpp)
  --swap-settings PATH  Path to modules/llama-swap-settings.nix to extract your model flags
  --target TAG        Compare to this tag (default: latest release, not master)
  --brief             One-line per matching commit
  --help              Show this help
EOF
}

REPO="ggml-org/llama.cpp"
TAG=""
CONFIG=""
SWAP_SETTINGS=""
TARGET=""
BRIEF=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2;;
    --tag) TAG="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --swap-settings) SWAP_SETTINGS="$2"; shift 2;;
    --target) TARGET="$2"; shift 2;;
    --brief) BRIEF=1; shift 1;;
    --help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

# Auto-detect project-local defaults if none supplied
if [[ -z "$TAG" && -z "$CONFIG" ]]; then
  for c in "@hosts/wsl/configuration.nix" "./configuration.nix" "./hosts/wsl/configuration.nix"; do
    if [[ -f "$c" ]]; then
      CONFIG="$c"
      echo "Auto-detected config: $CONFIG" >&2
      break
    fi
  done
fi

if [[ -z "$SWAP_SETTINGS" ]]; then
  for s in "@modules/llama-swap-settings.nix" "./modules/llama-swap-settings.nix" "./llama-swap-settings.nix"; do
    if [[ -f "$s" ]]; then
      SWAP_SETTINGS="$s"
      echo "Auto-detected swap-settings: $SWAP_SETTINGS" >&2
      break
    fi
  done
fi

if [[ -z "$TAG" && -z "$CONFIG" ]]; then
  echo "Either --tag or --config must be provided (no auto-detect found)" >&2
  usage
  exit 2
fi

if [[ -n "$CONFIG" ]]; then
  if [[ ! -f "$CONFIG" ]]; then
    echo "Config file not found: $CONFIG" >&2
    exit 2
  fi
  # Patterns: tag = "b9222", version = "9222", rev = "b9222", shortRev = "b9222",
  # fetchFromGitHub { rev = "b9222" }, or src = pkgs.fetchFromGitHub { rev = "b9222" }
  TAG_LINE=$(rg --hidden --no-messages '(tag|rev|shortRev)\s*=\s*"b[0-9]+' "$CONFIG" || true)
  if [[ -n "$TAG_LINE" ]]; then
    TAG=$(echo "$TAG_LINE" | sed -n 's/.*\(b[0-9][^"]*\)".*/\1/p' | head -n1)
  else
    # fall back to version = "9222"
    VER_LINE=$(rg --hidden --no-messages 'version\s*=\s*"[0-9]+' "$CONFIG" || true)
    if [[ -n "$VER_LINE" ]]; then
      VER=$(echo "$VER_LINE" | sed -n 's/.*version\s*=\s*"\([0-9][^"]*\)".*/\1/p' | head -n1)
      TAG="b${VER}"
    fi
  fi
  if [[ -z "$TAG" ]]; then
    echo "Could not detect tag in $CONFIG; try --tag manually" >&2
    exit 2
  fi
fi

# If swap settings provided, parse it to extract model flags to prioritize
PRIORITY_TERMS=()
if [[ -n "$SWAP_SETTINGS" ]]; then
  if [[ ! -f "$SWAP_SETTINGS" ]]; then
    echo "swap-settings file not found: $SWAP_SETTINGS" >&2
    exit 2
  fi
  # Read relevant flag tokens from the file. We look for common server args used in your models
  content=$(sed -n '1,4000p' "$SWAP_SETTINGS")
  # patterns we expect: --mmproj, mmproj-F16, --no-mmproj-offload, --flash-attn, --spec-type draft-mtp, --spec-draft-n-max 3
  # --cache-type-k q8_0, --cache-type-v q8_0, --ctx-size 131072, --ubatch-size 128, --threads 12, --ubatch-size
  extract() {
    echo "$content" | rg -o --no-line-number 'mmproj[-A-Za-z0-9_]*|no-mmproj-offload|flash-attn|spec-type[ =][A-Za-z0-9_-]+|spec-draft-n-max|cache-type-[kv] [a-z0-9_]+' -i || true
  }
  raw=$(extract)
  if [[ -n "$raw" ]]; then
    while IFS= read -r line; do
      # normalize
      term=$(echo "$line" | sed -E 's/\s+/ /g' | tr '[:upper:]' '[:lower:]' | sed -E 's/ /_/g')
      PRIORITY_TERMS+=("$term")
    done <<<"$raw"
  fi
  # also look for quant hints like Q5_K, Q4_K, q8_0 etc
  quant=$(echo "$content" | rg -o --no-line-number 'q8_0|q6_k|q5_k|q4_k|q[45]_k|UD-[A-Za-z0-9_]*' -i || true)
  if [[ -n "$quant" ]]; then
    while IFS= read -r q; do
      PRIORITY_TERMS+=("$(echo "$q" | tr '[:upper:]' '[:lower:]')")
    done <<<"$quant"
  fi
  # Also extract numeric parameter flags (--threads, --ctx-size, --ubatch-size, etc.)
  param_flags=$(echo "$content" | rg -o --no-line-number 'threads|ctx-size|ubatch-size|batch-size|parallel|flash-attn|presence-penalty|top-k|top-p|min-p|temperature' -i || true)
  if [[ -n "$param_flags" ]]; then
    while IFS= read -r p; do
      PRIORITY_TERMS+=("$(echo "$p" | tr '[:upper:]' '[:lower:]' | tr '-' '_')")
    done <<<"$param_flags"
  fi
fi

# Require gh and jq
command -v gh >/dev/null || { echo "gh (GitHub CLI) is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
command -v rg >/dev/null || { echo "rg (ripgrep) is required" >&2; exit 2; }

# Resolve target: explicit --target, or fetch latest release
if [[ -z "$TARGET" ]]; then
  LATEST_RELEASE=$(gh api -H "Accept: application/vnd.github+json" "repos/${REPO}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty')
  if [[ -n "$LATEST_RELEASE" ]]; then
    TARGET="$LATEST_RELEASE"
    echo "Latest release: ${TARGET}" >&2
  else
    echo "Could not fetch latest release; defaulting to master" >&2
    TARGET="master"
  fi
fi

# Build the keyword list: base keywords plus any priority terms from swap settings
BASE_KEYWORDS='(perf|performance|speed|optimi|tune|throughput|latency|cuda|pdl|flash-attn|flash|vulkan|metal|opencl|sycl|hexagon|adreno|rdna|bf16|fp16|quantiz|moe|mtp|speculat|draft|sampling|d2h|gpu|server|bench|batched-bench|fit-params|quantize|perplexity|ggml-cuda|ggml-zendnn|pdl)'

# merge priority terms into regex (escape)
if [[ ${#PRIORITY_TERMS[@]} -gt 0 ]]; then
  uniq_terms=($(printf "%s\n" "${PRIORITY_TERMS[@]}" | sort -u))
  priority_regex=$(printf '%s|' "${uniq_terms[@]}" | sed 's/|$//')
  # ensure we search word fragments — will be appended to the base regex
  KEYWORDS="${BASE_KEYWORDS}|(${priority_regex})"
else
  KEYWORDS="$BASE_KEYWORDS"
fi

# Fetch compare (with pagination for large ranges)
echo "Comparing ${REPO}:${TAG} -> ${TARGET}..." >&2
COMPARE_JSON=$(mktemp)

# GitHub API returns max 30 per page; loop until exhausted
fetch_compare_page() {
  local page=$1
  gh api \
    -H "Accept: application/vnd.github+json" \
    "repos/${REPO}/compare/${TAG}...${TARGET}?per_page=30&page=${page}"
}

# First pass: count total commits and fetch all pages
TOTAL_COMMITS=$(fetch_compare_page 1 | jq -r '.total_commits // 0')
if [[ "$TOTAL_COMMITS" -eq 0 ]]; then
  echo "gh compare failed or no commits found. Ensure the repo and tag exist and you have gh auth set up." >&2
  rm -f "$COMPARE_JSON"
  exit 3
fi

TOTAL_PAGES=$(( (TOTAL_COMMITS + 29) / 30 ))
if [[ $TOTAL_PAGES -gt 1 ]]; then
  echo "Found $TOTAL_COMMITS commits across $TOTAL_PAGES pages, fetching..." >&2
fi

for page in $(seq 1 "$TOTAL_PAGES"); do
  fetch_compare_page "$page" | jq -r '.commits[] | {sha: .sha, message: .commit.message, url: .html_url} | @base64' >> "$COMPARE_JSON"
done

if [[ ! -s "$COMPARE_JSON" ]]; then
  echo "No commits extracted from compare response." >&2
  rm -f "$COMPARE_JSON"
  exit 3
fi

# Load base64-encoded commit entries
COMMITS=$(cat "$COMPARE_JSON")

# Use Unit Separator (\x1f) as delimiter — safe for commit messages
SEP=$'\x1f'

decode() { echo "$1" | base64 --decode; }

MATCHED=()
PRIORITY_MATCHED=()

while IFS= read -r e; do
  [[ -z "$e" ]] && continue
  obj=$(decode "$e")
  msg=$(jq -r '.message' <<<"$obj" | tr '\n' ' ')
  url=$(jq -r '.url' <<<"$obj")
  sha=$(jq -r '.sha' <<<"$obj")
  lmsg=$(echo "$msg" | tr '[:upper:]' '[:lower:]')
  if echo "$lmsg" | grep -Ei "$KEYWORDS" >/dev/null; then
    # check if it matches any priority term (only terms actually found in swap-settings)
    is_priority=0
    if [[ ${#PRIORITY_TERMS[@]} -gt 0 ]]; then
      for t in "${PRIORITY_TERMS[@]}"; do
        tt=$(echo "$t" | tr '[:upper:]' '[:lower:]' | sed 's/_/ /g')
        if [[ -n "$tt" ]] && echo "$lmsg" | grep -Fqi "$tt" >/dev/null; then
          is_priority=1
          break
        fi
      done
    fi
    if [[ $is_priority -eq 1 ]]; then
      PRIORITY_MATCHED+=("${sha}${SEP}${msg}${SEP}${url}")
    else
      MATCHED+=("${sha}${SEP}${msg}${SEP}${url}")
    fi
  fi
done <<<"$COMMITS"

TOTAL_MATCHED=$(( ${#MATCHED[@]} + ${#PRIORITY_MATCHED[@]} ))
if [[ $TOTAL_MATCHED -eq 0 ]]; then
  echo "No performance-related commits detected in the diff (by keyword)." >&2
  echo "You can inspect the full commit list at: https://github.com/${REPO}/compare/${TAG}...${TARGET}"
  rm -f "$COMPARE_JSON"
  exit 0
fi

# Output header
echo
echo "Performance-related commits since ${REPO}:${TAG} -> ${TARGET}"
echo "(prioritized by your swap-settings if provided)"
echo

print_entry() {
  local item="$1"
  IFS="$SEP" read -r sha msg url <<<"$item"
  msg1=$(echo "$msg" | sed -E 's/\s+/ /g' | sed -E 's/\s*\(.*\)\s*//g' | cut -c1-300)
  echo "- ${msg1} — ${url}"
}

if [[ $BRIEF -eq 1 ]]; then
  # Brief mode: flat list, priority first
  for item in "${PRIORITY_MATCHED[@]}" "${MATCHED[@]}"; do
    print_entry "$item"
  done
else
  # Normal mode: priority header + grouped remaining
  if [[ ${#PRIORITY_MATCHED[@]} -gt 0 ]]; then
    echo "== High relevance to your configuration =="
    for item in "${PRIORITY_MATCHED[@]}"; do
      print_entry "$item"
    done
    echo
  fi
  # group the remaining matches with simple heuristics
  declare -A groups
  groups_order=(CUDA SYCL Vulkan Metal OpenCL Hexagon Quantization MTP/Speculative Server Tools App Other)
  for area in "${groups_order[@]}"; do groups["$area"]=""; done

  for item in "${MATCHED[@]}"; do
    IFS="$SEP" read -r sha msg url <<<"$item"
    lmsg=$(echo "$msg" | tr '[:upper:]' '[:lower:]')
    key="Other"
    if echo "$lmsg" | grep -Eqi 'cuda|pdl|ggml_cuda|cublas|nv' >/dev/null; then key="CUDA"; fi
    if echo "$lmsg" | grep -Eqi 'sycl|level zero|intel arc|arc|ggml_sycl' >/dev/null; then key="SYCL"; fi
    if echo "$lmsg" | grep -Eqi 'vulkan|spirv|vk_|ggml_vk|webgpu' >/dev/null; then key="Vulkan"; fi
    if echo "$lmsg" | grep -Eqi 'metal' >/dev/null; then key="Metal"; fi
    if echo "$lmsg" | grep -Eqi 'opencl|adreno|qualcomm|flash_attn' >/dev/null; then key="OpenCL"; fi
    if echo "$lmsg" | grep -Eqi 'hexagon|hmx|snapdragon' >/dev/null; then key="Hexagon"; fi
    if echo "$lmsg" | grep -Eqi 'quantiz|q8_|q6_|q5_|q4_|q_type|ggml-zendnn' >/dev/null; then key="Quantization"; fi
    if echo "$lmsg" | grep -Eqi 'mtp|speculat|draft|sampling|backend sampling|top_k' >/dev/null; then key="MTP/Speculative"; fi
    if echo "$lmsg" | grep -Eqi 'server|vram|slots|/slots|sleep' >/dev/null; then key="Server"; fi
    if echo "$lmsg" | grep -Eqi 'bench|batched-bench|fit-params|perplexity|quantize|tools|ui:|webui' >/dev/null; then key="Tools"; fi
    if echo "$lmsg" | grep -Eqi 'app :|unified executable|llama unified' >/dev/null; then key="App"; fi

    entry="- ${msg} — ${url}"
    groups["$key"]+="$entry\n"
  done

  for area in "${groups_order[@]}"; do
    if [[ -n "${groups[$area]}" ]]; then
      echo "== ${area} =="
      echo -e "${groups[$area]}"
      echo
    fi
  done

  if [[ -n "${groups[Other]}" ]]; then
    echo "== Other/General =="
    echo -e "${groups[Other]}"
    echo
  fi
fi

rm -f "$COMPARE_JSON"
echo "Total commits scanned: $TOTAL_COMMITS" >&2
exit 0
