# Returns the llama-swap settings attribute set.
#
# Usage:
#   services.llama-swap = {
#     enable = true;
#     settings = import ../../modules/llama-swap.nix {
#       llama-cpp-cuda = unstable-pkgs.llama-cpp.override { ... };
#       modelDir = "/var/lib/llama-models";
#     };
#   };
{
  llama-cpp-cuda,
  modelDir,
  lib,
}:

let
  llamaServer = "${llama-cpp-cuda}/bin/llama-server";
  mkCmd = args: lib.concatStringsSep " " (lib.filter (a: a != "") args);
in
{
  models = {
    # hf download ggml-org/bge-m3-Q8_0-GGUF --local-dir /var/lib/llama-models/ggml-org/bge-m3-Q8_0-GGUF --include "*q8*"
    "bge-m3" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/ggml-org/bge-m3-Q8_0-GGUF/bge-m3-q8_0.gguf"
        "--embeddings"
        "--ubatch-size 2048"
        "--port \${PORT}"
        "--device CUDA0"
        "-np 2"
        "--flash-attn on"
        "--ctx-size 8192"
        "--no-ui"
      ];
      # ttl = 600;
    };
    # hf download gpustack/bge-reranker-v2-m3-GGUF --local-dir /var/lib/llama-models/gpustack/bge-reranker-v2-m3-GGUF --include "*Q8*"
    "bge-reranker-v2-m3" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/gpustack/bge-reranker-v2-m3-GGUF/bge-reranker-v2-m3-Q8_0.gguf"
        "--reranking"
        "--ubatch-size 2048"
        "--port \${PORT}"
        "--device CUDA0"
        "-np 2"
        "--flash-attn on"
        "--ctx-size 8192"
        "--no-ui"
      ];
      # ttl = 600;
    };
    # hf download unsloth/gemma-4-12B-it-qat-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-12B-it-qat-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*" --include "mtp-*"
    # hf download google/gemma-4-12B-it-qat-q4_0-gguf --local-dir /var/lib/llama-models/google/gemma-4-12B-it-qat-q4_0-gguf
    "gemma-4-12b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/gemma-4-12B-it-qat-GGUF/gemma-4-12B-it-qat-UD-Q4_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/gemma-4-12B-it-qat-GGUF/mmproj-F16.gguf"
        # "--model ${modelDir}/google/gemma-4-12B-it-qat-q4_0-gguf/gemma-4-12b-it-qat-q4_0.gguf"
        # "--mmproj ${modelDir}/google/gemma-4-12B-it-qat-q4_0-gguf/mmproj-gemma-4-12b-it-qat-q4_0.gguf"
        "--port \${PORT}"
        "--device CUDA1"
        "-np 1"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 64"
        "--ctx-size 131072"
        "--spec-draft-device CUDA1"
        "--spec-type draft-mtp"
        "--spec-draft-n-max 2"
        "--spec-draft-model ${modelDir}/unsloth/gemma-4-12B-it-qat-GGUF/mtp-gemma-4-12B-it.gguf"
        "--no-ui"
      ];
      # ttl = 600;
    };
    # hf download unsloth/gemma-4-31B-it-qat-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-31B-it-qat-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*" --include "mtp-*"
    # hf download google/gemma-4-31B-it-qat-q4_0-gguf --local-dir /var/lib/llama-models/google/gemma-4-31B-it-qat-q4_0-gguf
    "gemma-4-31b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/gemma-4-31B-it-qat-GGUF/gemma-4-31B-it-qat-UD-Q4_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/gemma-4-31B-it-qat-GGUF/mmproj-F16.gguf"
        # "--model ${modelDir}/google/gemma-4-31B-it-qat-q4_0-gguf/gemma-4-31B_q4_0-it.gguf"
        # "--mmproj ${modelDir}/google/gemma-4-31B-it-qat-q4_0-gguf/gemma-4-31B-it-mmproj.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 64"
        "--ctx-size 131072"
        "--spec-draft-device CUDA1"
        "--spec-type draft-mtp"
        "--spec-draft-n-max 2"
        "--spec-draft-model ${modelDir}/unsloth/gemma-4-31B-it-qat-GGUF/mtp-gemma-4-31B-it.gguf"
        "--threads 12"
        "--no-ui"
      ];
      # ttl = 600;
    };
    # hf download unsloth/Qwen3.8-27B-GGUF --local-dir /var/lib/llama-models/unsloth/Qwen3.8-27B-GGUF --include "*mmproj-F16*" --include "*UD-Q5_K_XL*"
    "qwen-3-8-27b-mtp" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q5_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/Qwen3.8-27B-GGUF/mmproj-F16.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 20"
        "--presence-penalty 0.0"
        "--ctx-size 131072"
        "--threads 12"
        "--spec-type draft-mtp"
        # "--spec-type draft-mtp,ngram-mod"
        "--spec-draft-n-max 3"
        # "--spec-ngram-mod-n-match 24"
        # "--spec-ngram-mod-n-min 48"
        # "--spec-ngram-mod-n-max 64"
        "--no-ui"
      ];
      # ttl = 600;
    };
    # hf download ornith-ai/Ornith-1.5-35B-A3B-GGUF --local-dir /var/lib/llama-models/ornith-ai/Ornith-1.5-35B-A3B-GGUF --include "mmproj*" --include "*Q5_K_M*"
    "ornith-1-5-35b-a3b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/ornith-ai/Ornith-1.5-35B-A3B-GGUF/Ornith-1.5-35B-Q5_K_M.gguf"
        "--mmproj ${modelDir}/ornith-ai/Ornith-1.5-35B-A3B-GGUF/mmproj-Ornith-1.5-35B-BF16.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--ctx-size 131072"
        "--temp 1.0" # 0.6 for general tasks?
        "--top-p 0.95"
        "--top-k 20"
        "--no-ui"
      ];
      # ttl = 600;
    };
    # see https://github.com/ggml-org/llama.cpp/pull/25165
    # hf download unsloth/Laguna-S-2.1-GGUF --local-dir /var/lib/llama-models/unsloth/Laguna-S-2.1-GGUF --include "*UD-IQ4_NL*"
    # hf download poolside/Laguna-S-2.1-GGUF --local-dir /var/lib/llama-models/poolside/Laguna-S-2.1-GGUF --include "*DFlash*"
    "laguna-s-21" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/Laguna-S-2.1-GGUF/UD-IQ4_NL/Laguna-S-2.1-UD-IQ4_NL-00001-of-00003.gguf"
        # "--spec-type draft-dflash"
        # "--spec-draft-n-max 15"
        # "--spec-draft-model ${modelDir}/poolside/Laguna-S-2.1-GGUF/laguna-s-2.1-DFlash-BF16.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--ctx-size 131072"
        "--threads 12"
        "--load-mode none"
        # "--cache-type-k q8_0"
        # "--cache-type-v q8_0"
        # --n-cpu-moe 46, -ngl 99
        "--no-ui"
      ];
      # ttl = 600;
    };
    # hf download meta-models/Muse-Glimmer-30B-GGUF --local-dir /var/lib/llama-models/meta-models/muse-glimmer-30B-GGUF --include "*Q4_K_XL*"
    # hf download meta-models/Muse-Glimmer-30B-GGUF --local-dir /var/lib/llama-models/meta-models/muse-glimmer-30B-GGUF --include "mmproj*"
    # hf download meta-models/Muse-Glimmer-30B-GGUF --local-dir /var/lib/llama-models/meta-models/muse-glimmer-30B-GGUF --include "dflash*"
    "muse-glimmer-30b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/meta-models/muse-glimmer-30B-GGUF/Muse-Glimmer-30B-KQuant-Dynamic-Q4_K_XL.gguf"
        "--mmproj ${modelDir}/meta-models/muse-glimmer-30B-GGUF/mmproj-kquant.gguf"
        "--spec-type draft-dflash"
        "--spec-draft-n-max 15"
        "--spec-draft-model ${modelDir}/meta-models/muse-glimmer-30B-GGUF/dflash-kquant.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 64"
        "--ctx-size 131072"
        "--threads 12"
        "--no-ui"
      ];
      # ttl = 600;
    };
  };
}
