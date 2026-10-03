# Model Downloads

Models are stored on Windows:

```
/mnt/f/llama-models/
```

Downloads are run manually from NixOS WSL using the `hf` command.

## bge-m3

```sh
hf download ggml-org/bge-m3-Q8_0-GGUF --local-dir /mnt/f/llama-models/ggml-org/bge-m3-Q8_0-GGUF --include "*q8*"
```

## bge-reranker-v2-m3

```sh
hf download gpustack/bge-reranker-v2-m3-GGUF --local-dir /mnt/f/llama-models/gpustack/bge-reranker-v2-m3-GGUF --include "*Q8*"
```

## gemma-4-12b

```sh
hf download unsloth/gemma-4-12B-it-qat-GGUF --local-dir /mnt/f/llama-models/unsloth/gemma-4-12B-it-qat-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*" --include "mtp-*"
hf download google/gemma-4-12B-it-qat-q4_0-gguf --local-dir /mnt/f/llama-models/google/gemma-4-12B-it-qat-q4_0-gguf
```

## gemma-4-31b

```sh
hf download unsloth/gemma-4-31B-it-qat-GGUF --local-dir /mnt/f/llama-models/unsloth/gemma-4-31B-it-qat-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*" --include "mtp-*"
hf download google/gemma-4-31B-it-qat-q4_0-gguf --local-dir /mnt/f/llama-models/google/gemma-4-31B-it-qat-q4_0-gguf
```

## qwen-3-8-27b-mtp

```sh
hf download unsloth/Qwen3.8-27B-GGUF --local-dir /mnt/f/llama-models/unsloth/Qwen3.8-27B-GGUF --include "*mmproj-F16*" --include "*UD-Q5_K_XL*"
```

## ornith-1-5-35b-a3b

```sh
hf download ornith-ai/Ornith-1.5-35B-A3B-GGUF --local-dir /mnt/f/llama-models/ornith-ai/Ornith-1.5-35B-A3B-GGUF --include "mmproj*" --include "*Q5_K_M*"
```

## laguna-s-21

See https://github.com/ggml-org/llama.cpp/pull/25165

```sh
hf download unsloth/Laguna-S-2.1-GGUF --local-dir /mnt/f/llama-models/unsloth/Laguna-S-2.1-GGUF --include "*UD-IQ4_NL*"
hf download poolside/Laguna-S-2.1-GGUF --local-dir /mnt/f/llama-models/poolside/Laguna-S-2.1-GGUF --include "*DFlash*"
```

## muse-glimmer-30b

```sh
hf download meta-models/Muse-Glimmer-30B-GGUF --local-dir /mnt/f/llama-models/meta-models/muse-glimmer-30B-GGUF --include "*Q4_K_XL*"
hf download meta-models/Muse-Glimmer-30B-GGUF --local-dir /mnt/f/llama-models/meta-models/muse-glimmer-30B-GGUF --include "mmproj*"
hf download meta-models/Muse-Glimmer-30B-GGUF --local-dir /mnt/f/llama-models/meta-models/muse-glimmer-30B-GGUF --include "dflash*"
```

## qwen-3-8-flash-next

```sh
export HF_HUB_DISABLE_XET=1
hf download unsloth/Qwen3.8-Flash-Next-GGUF --local-dir /mnt/f/llama-models/unsloth/Qwen3.8-Flash-Next-GGUF --include "*UD-Q3_K_XL*"
hf download unsloth/Qwen3.8-Flash-Next-GGUF --local-dir /mnt/f/llama-models/unsloth/Qwen3.8-Flash-Next-GGUF --include "*UD-IQ4_XS*"
hf download unsloth/Qwen3.8-Flash-Next-GGUF --local-dir /mnt/f/llama-models/unsloth/Qwen3.8-Flash-Next-GGUF --include "*UD-Q4_K_XL*"
hf download unsloth/Qwen3.8-Flash-Next-GGUF --local-dir /mnt/f/llama-models/unsloth/Qwen3.8-Flash-Next-GGUF --include "mmproj-F16*"
hf download ggml-org/Qwen3.8-Flash-Next-GGUF --local-dir /mnt/f/llama-models/ggml-org/Qwen3.8-Flash-Next-GGUF --include "mtp-Qwen3.8-Flash-Next-Q4_0.gguf"
```
