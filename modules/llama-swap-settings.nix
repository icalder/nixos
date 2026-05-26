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
    # hf download unsloth/gemma-4-E4B-it-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-E4B-it-GGUF --include "*mmproj-F16*" --include "*UD-Q5_K_XL*"
    "gemma-4-e4b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-UD-Q5_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/gemma-4-E4B-it-GGUF/mmproj-F16.gguf"
        "--port \${PORT}"
        "--device CUDA1"
        "-np 2"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 64"
        "--ctx-size 131072"
        "--no-ui"
      ];
      ttl = 600;
    };
    # hf download unsloth/gemma-4-26B-A4B-it-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-26B-A4B-it-GGUF --include "*mmproj-F16*" --include "*UD-Q5_K_XL*"
    # hf download ji-farthing/gemma-4-26B-A4B-it-assistant-Q6_K-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-26B-A4B-it-GGUF --include "*Q6_K*"
    # --spec-draft-model ${modelDir}/unsloth/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-assistant-Q6_K.gguf
    # --spec-type draft-simple # or --draft-mtp?
    # --spec-draft-n-max 3
    # https://github.com/ggml-org/llama.cpp/issues/23161
    "gemma-4-26b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q5_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/gemma-4-26B-A4B-it-GGUF/mmproj-F16.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 64"
        "--ctx-size 131072"
        "--no-ui"
      ];
      ttl = 600;
    };
    # hf download unsloth/gemma-4-31B-it-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-31B-it-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*"
    "gemma-4-31b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/gemma-4-31B-it-GGUF/gemma-4-31B-it-UD-Q4_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/gemma-4-31B-it-GGUF/mmproj-F16.gguf"
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
      ttl = 600;
    };
    # hf download unsloth/granite-4.1-30b-GGUF --local-dir /var/lib/llama-models/unsloth/granite-4.1-30b-GGUF --include "*UD-Q4_K_XL*"
    "granite-4.1-30b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/granite-4.1-30b-GGUF/granite-4.1-30b-UD-Q4_K_XL.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 64"
        "--ctx-size 131072"
        "--cache-type-k q8_0"
        "--cache-type-v q8_0"
        "--threads 12"
        "--no-ui"
      ];
      ttl = 600;
    };
    # hf download unsloth/Qwen3.5-9B-GGUF --local-dir /var/lib/llama-models/unsloth/Qwen3.5-9B-GGUF --include "*mmproj-F16*" --include "*UD-Q5_K_XL*"
    "qwen-3-5-9b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/Qwen3.5-9B-GGUF/Qwen3.5-9B-UD-Q5_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/Qwen3.5-9B-GGUF/mmproj-F16.gguf"
        "--port \${PORT}"
        "--device CUDA1"
        "-np 1"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 20"
        "--min-p 0.00"
        "--ctx-size 131072"
        "--no-ui"
      ];
      ttl = 600;
    };
    # hf download unsloth/Qwen3.6-35B-A3B-MTP-GGUF --local-dir /var/lib/llama-models/unsloth/Qwen3.6-35B-A3B-MTP-GGUF --include "*mmproj-F16*" --include "*UD-Q5_K_XL*"
    "qwen-3-6-35b-mtp" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/mmproj-F16.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--temp 0.6"
        "--top-p 0.95"
        "--top-k 20"
        "--presence-penalty 0.5"
        "--ctx-size 131072"
        "--spec-type draft-mtp"
        "--spec-draft-n-max 3"
        "--no-ui"
      ];
      ttl = 600;
    };
    # hf download unsloth/Qwen3.6-27B-MTP-GGUF --local-dir /var/lib/llama-models/unsloth/Qwen3.6-27B-MTP-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*"
    "qwen-3-6-27b-mtp" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/Qwen3.6-27B-MTP-GGUF/Qwen3.6-27B-UD-Q4_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/Qwen3.6-27B-MTP-GGUF/mmproj-F16.gguf"
        "--port \${PORT}"
        "-np 1"
        "--flash-attn on"
        "--temp 0.6"
        "--top-p 0.95"
        "--top-k 20"
        "--presence-penalty 0.0"
        "--ctx-size 131072"
        "--threads 12"
        "--spec-type draft-mtp"
        "--spec-draft-n-max 3"
        "--no-ui"
      ];
      ttl = 600;
    };
  };
}
