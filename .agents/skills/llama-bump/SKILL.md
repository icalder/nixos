---
name: llama-bump
description: Bump llama.cpp to a new build tag in hosts/wsl/configuration.nix. Updates version, src hash, and npmDepsHash automatically via iterative nix builds. Use when asked to upgrade, bump, or update llama.cpp to a new build number.
---

# llama-bump

Bump llama.cpp to a new build tag (e.g. b9294) in the NixOS WSL configuration.

## Prerequisites

- `nix` with flakes enabled
- Working flake at `/home/itcalde/nixos`
- Network access to GitHub (for fetching source) and cache.nixos-cuda.org

## Usage

```bash
./scripts/bump.sh <new-version>
```

Where `<new-version>` is the build number **without** the `b` prefix (e.g. `9294` for `b9294`).

## Workflow (for the agent)

If the user does not provide a version, **prompt them** for it first. Then follow these steps:

### 1. Read the current configuration

Read `@hosts/wsl/configuration.nix` to locate the llama-cpp-cuda override block.

### 1a. No-op check

If the current `version` already matches the target, **stop immediately**. Report: "Already at bXXXX. Nothing to do." Do not run any builds.

### 2. Update version and set fake hashes

In the `overrideAttrs` block, make three changes in one `edit` call:
- Set `version` to the new build number (e.g. `"9294"`)
- Set `src.hash` to `lib.fakeHash`
- Set `npmDepsHash` to `lib.fakeHash`

### 3. First build — extract src hash

Run:
```bash
nix build .#nixosConfigurations.nixos.config.system.build.toplevel 2>&1 | head -30
```

Look for the hash mismatch error. The `got:` value is the correct src hash, e.g.:
```
specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
   got:    sha256-fnxc7GtjVoGdbsy0Xtzx1gBHhpcYS2rlT/NqaQOFy8E=
```

### 4. Patch the src hash

Replace `lib.fakeHash` in the `src` block with the real hash from step 3.

### 5. Second build — extract npmDepsHash

Run the same build command again. Look for the second hash mismatch:
```
specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
   got:    sha256-Iyg8FpcTKf2UYHuK7mA3cTAqVaLcQPcS0YCa5Qf01Gc=
```

### 6. Patch the npmDepsHash

Replace `lib.fakeHash` in the `npmDepsHash` line with the real hash from step 5.

### 7. Verify and stop

Read the updated file to confirm all three values are correct. Report the changes to the user. **Do not** run a final full build — the user will do that themselves.

## Summary Table Format

Always present the final result as a comparison table:

| Field | Old (bXXXX) | New (bYYYY) |
|---|---|---|
| `version` | `"XXXX"` | `"YYYY"` |
| `src.hash` | `sha256-...` | `sha256-...` |
| `npmDepsHash` | `sha256-...` | `sha256-...` |

## Notes

- The tag format is always `b${version}` (e.g. `b9294`)
- The repository is `ggml-org/llama.cpp` (inherited from `oldAttrs.src`)
- Both hashes use `sha256-` prefix (SRI format)
- The `npmRoot` is `"tools/ui"` — do not change this
- Keep any existing `cmakeFlags`, `preConfigure`, or other overrides untouched
