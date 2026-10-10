---
name: llama-windows-audit
description: Compare the currently deployed Windows llama.cpp build to the latest release and produce a focused, performance-oriented summary (CUDA/SYCL/Vulkan/OpenCL/quantization/server/tools, etc.).
---

# llama-windows-audit

## What it does

This skill reads the **currently deployed** llama.cpp build tag from the Windows
install manifest, then compares it to the latest published GitHub release —
producing the same focused, performance-oriented summary as
[llama-performance-audit](https://), but without needing a Nix config.

It is designed for the WSL workflow where the Windows llama.cpp binaries live in
`~/winhome/llama-cpp` and are tracked by a `.llama-cpp-manifest` file written by
`update-llama-cpp.sh`.

## Where to find your Windows install

The manifest file lives at:

```
~/winhome/llama-cpp/.llama-cpp-manifest
```

It contains a header line like:

```
# build: b11429
```

This is the file the script reads by default to determine your base tag. If the
manifest is absent or you want to compare against a different starting point,
use `--tag`.

The update script that manages this install is at:

```
./windows-scripts/llama.cpp/update-llama-cpp.sh
```

All paths below are relative to the repository root (`./nixos`).

---

## Where to find your Windows llama-swap config

The **actual** llama-swap configuration file (not the Nix module) lives at:

```
~/winhome/scoop/persist/llama-swap/config.yaml
```

It contains per-model `cmd:` blocks with the real llama.cpp flags you deployed,
e.g.:

```yaml
models:
  gemma-4-12b:
    cmd: C:/Users/iainc/llama-cpp/llama-server.exe
      --model F:/llama-models/unsloth/gemma-4-12B-it-qat-GGUF/gemma-4-12B-it-qat-UD-Q4_K_XL.gguf
      --mmproj F:/llama-models/unsloth/gemma-4-12B-it-qat-GGUF/mmproj-F16.gguf
      --port ${PORT} --device CUDA1 -np 1 --flash-attn on --ctx-size 131072 --no-ui
      --spec-type draft-mtp --spec-draft-device CUDA1 --spec-draft-n-max 2
      --spec-draft-model F:/llama-models/unsloth/gemma-4-12B-it-qat-GGUF/mtp-gemma-4-12B-it.gguf
```

**This file is the source of truth** for your deployed flags. The script reads
it by default to extract priority terms (e.g. `flash-attn`, `cuda1`,
`spec-type`, `ud-q4_k_xl`, `ctx-size`, `mmproj`, `threads`). The Nix module at
`modules/llama-swap-settings.nix` describes the WSL/NixOS deployment and is
used as a fallback only when the Windows YAML is absent.

To override the config file, use `--swap-settings PATH` (`.yaml` or `.nix`).

## How it works

1. **Read the base tag** from `~/winhome/llama-cpp/.llama-cpp-manifest`
   (the `# build:` line). Override with `--tag` if the manifest is missing.
2. **Read your llama-swap config** from the Windows YAML
   (`~/winhome/scoop/persist/llama-swap/config.yaml` by default) to extract
   which model flags and parameters you actually use, and boost commits that
   mention those terms to the top of the report.
3. Call the GitHub API via `gh` to compare that tag to the latest published
   release (not master).
4. Filter commits for performance- and backend-related changes and print a
   concise summary, prioritizing commits relevant to your configuration
   (mmproj, flash-attn, spec/mTP, cache types, quantization, context sizes,
   ubatch, threads, etc.).

It assumes `node` and `gh` (GitHub CLI) are available in PATH and authenticated.

## Files

- `llama-win-audit.js` — the executable Node.js script
- `../_shared/llama-audit-core.js` — shared audit logic (also used by
  `llama-performance-audit`)

## Usage

- From the skill directory (auto-detects the Windows YAML config and manifest):

  ```
  ./llama-win-audit.js
  ```

  or with an explicit config file:

  ```
  ./llama-win-audit.js --swap-settings ~/winhome/scoop/persist/llama-swap/config.yaml
  ```

  or with an explicit install directory:

  ```
  ./llama-win-audit.js --win-dir ~/winhome/llama-cpp --swap-settings ~/winhome/scoop/persist/llama-swap/config.yaml
  ```

  or with an explicit base tag (bypasses manifest reading):

  ```
  ./llama-win-audit.js --tag b11429
  ```

  or to compare against a specific target instead of the latest release:

  ```
  ./llama-win-audit.js --tag b11429 --target master
  ```

### Options

| Option | Description |
|---|---|
| `--win-dir PATH` | Windows llama.cpp install directory (default: `~/winhome/llama-cpp`) |
| `--tag TAG` | Use an explicit Git tag (e.g. `b11429`) instead of reading the manifest |
| `--repo OWNER/REPO` | GitHub repository (default: `ggml-org/llama.cpp`) |
| `--swap-settings PATH` | Path to a swap-settings config file. `.yaml`/`.yml` uses YAML-aware extraction (reads only `cmd:` blocks); `.nix` uses full-file extraction. Defaults to the Windows YAML config. |
| `--target TAG` | Compare to this tag instead of the latest release (e.g. `master`, `b9400`) |
| `--brief` | Short condensed output (one-line per commit) |
| `--help` | Show usage |

### Behavior changes vs. default

- **Tag source**: the base tag is read from the Windows manifest
  (`~/winhome/llama-cpp/.llama-cpp-manifest`) rather than a Nix configuration.
  This captures exactly what is deployed on your Windows machine.
- **Config source**: priority terms are extracted from the **Windows
  llama-swap YAML config** (`~/winhome/scoop/persist/llama-swap/config.yaml`)
  by default, not the local Nix module. The YAML extractor reads only the
  `cmd:` continuation lines (flags starting with `--`), ignoring comments and
  YAML structure, while filtering out file paths and numeric-only values.
- **Default comparison target** is the **most recently published release**
  (fetched via GitHub API, including prereleases). This is important for repos
  like llama.cpp whose `b<N>` build tags are marked as prereleases — GitHub's
  `releases/latest` endpoint skips them, which would compare against an older
  formal release. Use `--target master` to compare against master instead.

### Notes

- The script uses a keyword heuristic; it is configurable via the shared core
  module (`../_shared/llama-audit-core.js`). If you want narrower or broader
  matching for your models, you can tune the `BASE_KEYWORDS` constant or the
  term-extraction functions there.
- The `extractFlagsFromString` helper in the shared core is a pure function
  that works on any text containing llama.cpp flags — it's shared by both the
  Nix extractor (`extractPriorityTerms`) and the YAML extractor
  (`extractPriorityTermsFromYaml`).
- Pagination is automatic: the script loops through all GitHub API pages
  (30 commits/page) until the full diff is fetched.
- The manifest parser recognizes the `# build: bXXXXX` header line.

## Agent Response Format

After running the script, synthesize its raw output into a structured report
with the same sections as llama-performance-audit:

### 1. Header line
```
## Performance Audit: <tag> → <target> (<N> commits)
```

### 2. High Impact table (🔴)
Only commits from the script's "High relevance to your configuration" section.

### 3. Backend Improvements (🟡)
Grouped by backend (SYCL, Vulkan, Metal, OpenCL, Hexagon).

### 4. Quantization (🟡)
Bullet list of quant-related changes.

### 5. Server (🟢)
Bullet list of server-side changes.

### 6. Other notable changes (🟢)

### 7. Upgrade Recommendation

Use emoji impact markers: 🔴 high, 🟡 medium, 🟢 low. Always include the upgrade
recommendation section. See `llama-performance-audit/SKILL.md` for the full
response format details.
