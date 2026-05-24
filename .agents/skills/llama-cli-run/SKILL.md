---
name: llama-cli-run
description: Generate a full llama-cli command from a model defined in modules/llama-swap-settings.nix. Prompts for the model name if not provided. Transforms llama-server commands to llama-cli by removing server-only flags and adding interactive mode flags.
---

# llama-cli-run

Generate a ready-to-paste `llama-cli` command from a model defined in `modules/llama-swap-settings.nix`.

## Prerequisites

- Working flake at `/home/itcalde/nixos`
- The file `modules/llama-swap-settings.nix` must exist

## Workflow

### 1. Read the model definitions

Read `modules/llama-swap-settings.nix` to find the model's `cmd` block. The `cmd` is built using `mkCmd` which joins array elements with spaces.

### 2. Identify the model

If the user provides a model name, use it directly. If not, list all available models (e.g. `gemma-4-31b`, `qwen-3-6-27b-mtp`, etc.) and **prompt them** to choose one.

### 3. Transform llama-server → llama-cli

Apply these transformations to the command array. **All flags not mentioned below are preserved as-is.**

#### Remove (server-only flags — never valid for llama-cli)

| Flag | Reason |
|---|---|
| `llama-server` | Replace with `llama-cli` |
| `--port ${PORT}` | llama-cli is interactive, no server |
| `--no-ui` | Server-only UI toggle |
| `-np <N>` | Server slot count |

#### Do NOT add

- Do **not** add `-c` / `--ctx-size` duplicate if `--ctx-size` is already present
- Do **not** add `--spec-draft-model` unless it is already in the source command (it is commented out in the config)
- Do **not** add `-p "<prompt>"` unless the user explicitly provides a prompt

### 4. Resolve paths

Expand `${modelDir}` using the actual path from the Nix file's function signature parameter. The `modelDir` is passed when the module is imported (typically `/var/lib/llama-models`). If the exact value cannot be determined, use `$MODEL_DIR` as a placeholder and note it.

### 5. Output

Present the final command in a code block, ready to copy-paste. Each flag on its own line with `\` continuation:

```bash
llama-cli \
  --model /path/to/model.gguf \
  --mmproj /path/to/mmproj.gguf \
  --no-mmproj-offload \
  --flash-attn on \
  --temp 1.0 \
  --top-p 0.95 \
  --top-k 64 \
  --ctx-size 131072
```

## Notes

- The `--spec-draft-model` flag is commented out in the source config — do not include it unless the user explicitly asks
- If the model has an `mmproj` flag in the source, keep it for vision support
- Always mention that `--port` was removed because `llama-cli` is interactive (no server)
- If the model name is ambiguous or not found, list all available models and ask the user to clarify
- **Key principle:** Only the flags listed in the "Remove" section are stripped. Every other flag in the original command is preserved, including any future flags added to the config.
