---
name: llama-performance-audit
description: Compare a llama.cpp tag (or a Nix configuration) to the latest release and produce a focused, performance-oriented summary (CUDA/SYCL/Vulkan/OpenCL/quantization/server/tools, etc.).
---

# llama-performance-audit

## Where to find your Nix configuration

The llama.cpp package override (build tag, source hash, npmDepsHash) lives in:

```
./hosts/wsl/configuration.nix
```

This is the file to pass to `--config` when auditing your current setup. The llama-swap settings (model flags and parameters) are in:

```
./modules/llama-swap-settings.nix
```

All paths below are relative to the repository root (`./nixos`).

---

This skill provides a CLI script that repeats the steps I used earlier and can be focused using your llama-swap settings:
- read a Nix config (or accept a tag) to determine which llama.cpp tag was used (e.g. b9222)
- optionally read your llama-swap settings file (modules/llama-swap-settings.nix) to extract which model flags and parameters you actually use
- call the GitHub API via `gh` to compare that tag to the latest published release (not master)
- filter commits for performance- and backend-related changes and print a concise summary, prioritizing commits relevant to your configuration (mmproj, flash-attn, spec/mTP, cache types, quantization, context sizes, ubatch, threads, etc.)

It assumes `gh` (GitHub CLI), `jq`, and `rg` (ripgrep) are available in PATH and authenticated.

Files provided
- llama-audit.sh — the executable script that performs the audit

Usage

- From the skill directory:

  ./llama-audit.sh --config PATH/TO/configuration.nix --swap-settings PATH/TO/modules/llama-swap-settings.nix

  or

  ./llama-audit.sh --tag b9222 --repo ggml-org/llama.cpp --swap-settings @modules/llama-swap-settings.nix

  or to compare against a specific tag instead of the latest release:

  ./llama-audit.sh --tag b9222 --target b9400 --swap-settings @modules/llama-swap-settings.nix

Options
- --config <path> : Parse a Nix configuration to extract a tag or version (preferred when auditing your config)
- --tag <tag> : Use an explicit Git tag (e.g. b9222)
- --repo <owner/repo> : GitHub repository (default: ggml-org/llama.cpp)
- --swap-settings <path> : Path to your llama-swap-settings.nix (used to extract model flags to prioritize)
- --target <tag> : Compare to this tag instead of the latest release (e.g. `master`, `b9400`)
- --brief : Short condensed output (one-line per commit)
- --help : Show usage

Behavior changes vs. default
- When --swap-settings is provided, the script extracts model-specific flags and token patterns (examples: mmproj, no-mmproj-offload, flash-attn, spec-type/draft-mtp, spec-draft-n-max, cache-type-k/v, q8_0/q6/q5/q4, ctx-size, ubatch-size, threads, presence-penalty, top-k/top-p) and boosts commits that mention those terms to the top of the report.

Notes
- The script uses a keyword heuristic; it is configurable. If you want narrower or broader matching for your models, I can tune the token list or add explicit per-model rules.
- Pagination is automatic: the script loops through all GitHub API pages (30 commits/page) until the full diff is fetched.
- The Nix config parser recognizes `tag`, `rev`, `shortRev`, and `version` fields (including inside `fetchFromGitHub` blocks).
- Priority terms are extracted **only** from your swap-settings file — no unconditional defaults are added.
- Default comparison target is the **latest published release** (fetched via GitHub API). Use `--target master` to compare against master instead.

Example output

```
$ ./llama-audit.sh --tag b9222 --swap-settings @modules/llama-swap-settings.nix
# Latest release: b9400
# Comparing ggml-org/llama.cpp:b9222 -> b9400...

Performance-related commits since ggml-org/llama.cpp:b9222 -> b9400
(prioritized by your swap-settings if provided)

== High relevance to your configuration ==
- flash-attn: fix qkv layout for non-power-of-2 ctx — https://github.com/ggml-org/llama.cpp/commit/abc123
- cache-type-k/v: allow per-slot quant override — https://github.com/ggml-org/llama.cpp/commit/def456

== CUDA ==
- ggml-cuda: improve PDL kernel for Hopper — https://github.com/ggml-org/llama.cpp/commit/111

== Quantization ==
- quantize: add Q4_K_XS variant with improved accuracy — https://github.com/ggml-org/llama.cpp/commit/222

== Server ==
- server: fix slot timeout on idle connections — https://github.com/ggml-org/llama.cpp/commit/333

Total commits scanned: 847
```

## Agent Response Format

After running the script, synthesize its raw output into a structured report with these sections:

### 1. Header line
```
## Performance Audit: <tag> → master (<N> commits)
```

### 2. High Impact table (🔴)
Only commits from the script's "High relevance to your configuration" section. Use a markdown table:

| Area | What changed | Why it matters |
|---|---|---|
| **CUDA PDL** | Programmatic Dependent Launch... | If you're on Hopper, enable via...

- **Area**: short label, bold
- **What changed**: one-line summary of the commit(s)
- **Why it matters**: concrete impact for the user's hardware/config, with any new flags or env vars

### 3. Backend Improvements (🟡)
Grouped by backend (SYCL, Vulkan, Metal, OpenCL, Hexagon). Bullet list, one line per commit:
```
- **SYCL**: BF16 DMMV kernel path (~4x speedup on Intel Arc), MoE prefill improvement
```

### 4. Quantization (🟡)
Bullet list of quant-related changes with backend prefix.

### 5. Server (🟢)
Bullet list of server-side changes.

### 6. Other notable changes (🟢)
Unified executable, CI/build changes, etc. Keep brief.

### 7. Upgrade Recommendation
End with a short section:
```
### Upgrade Recommendation

**Worth upgrading** primarily for:
1. **<feature>** — <reason>
2. **<fix>** — <reason>

The <N>-commit gap is manageable/unmanageable. <Any breaking changes>.
```

Rules:
- Use emoji impact markers: 🔴 high (user's config), 🟡 medium (backend relevant to user), 🟢 low (general)
- Omit sections with no entries
- Keep each bullet to one line; link commit URLs only if they add context
- Always include the upgrade recommendation section

Next steps (optional)
- Add a grouped HTML/Markdown report highlighting the most relevant commits for your exact flags
- Make the script produce a short upgrade-action checklist (e.g., "Enable GGML_CUDA_PDL on Hopper to get PDL improvements") based on matched commits
- Wire this skill into the pi TUI as an action
