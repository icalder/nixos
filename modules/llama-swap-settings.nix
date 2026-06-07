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
    # hf download unsloth/gemma-4-12B-it-qat-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-12B-it-qat-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*"
    # hf download google/gemma-4-12B-it-qat-q4_0-gguf --local-dir /var/lib/llama-models/google/gemma-4-12B-it-qat-q4_0-gguf
    "gemma-4-12b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/gemma-4-12B-it-qat-GGUF/gemma-4-12B-it-qat-UD-Q4_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/gemma-4-12B-it-qat-GGUF/mmproj-F16.gguf"
        # "--model ${modelDir}/google/gemma-4-12B-it-qat-q4_0-gguf/gemma-4-12b-it-qat-q4_0.gguf"
        # "--mmproj ${modelDir}/google/gemma-4-12B-it-qat-q4_0-gguf/mmproj-gemma-4-12b-it-qat-q4_0.gguf"
        "--port \${PORT}"
        "--device CUDA0"
        "-np 1"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 64"
        "--ctx-size 131072"
        "--no-ui"
      ];
      # ttl = 600;
    };
    # hf download unsloth/gemma-4-31B-it-qat-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-31B-it-qat-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*"
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
        "--threads 12"
        "--no-ui"
      ];
      # ttl = 600;
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
      # ttl = 600;
    };
    # hf download unsloth/Qwen3.5-9B-GGUF --local-dir /var/lib/llama-models/unsloth/Qwen3.5-9B-GGUF --include "*mmproj-F16*" --include "*UD-Q5_K_XL*"
    "qwen-3-5-9b" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/Qwen3.5-9B-GGUF/Qwen3.5-9B-UD-Q5_K_XL.gguf"
        "--mmproj ${modelDir}/unsloth/Qwen3.5-9B-GGUF/mmproj-F16.gguf"
        "--port \${PORT}"
        "--device CUDA1"
        "-np 2"
        "--flash-attn on"
        "--temp 1.0"
        "--top-p 0.95"
        "--top-k 20"
        "--min-p 0.00"
        "--ctx-size 131072"
        "--no-ui"
      ];
      # ttl = 600;
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
        # "--spec-type draft-mtp,ngram-mod"
        "--spec-draft-n-max 3"
        # "--spec-ngram-mod-n-match 24"
        # "--spec-ngram-mod-n-min 48"
        # "--spec-ngram-mod-n-max 64"
        "--no-ui"
      ];
      # ttl = 600;
    };
    # hf download unsloth/Qwen3.6-27B-MTP-GGUF --local-dir /var/lib/llama-models/unsloth/Qwen3.6-27B-MTP-GGUF --include "*mmproj-F16*" --include "*UD-Q5_K_XL*"
    "qwen-3-6-27b-mtp" = {
      cmd = mkCmd [
        "${llamaServer}"
        "--model ${modelDir}/unsloth/Qwen3.6-27B-MTP-GGUF/Qwen3.6-27B-UD-Q5_K_XL.gguf"
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
        # "--spec-type draft-mtp,ngram-mod"
        "--spec-draft-n-max 3"
        # "--spec-ngram-mod-n-match 24"
        # "--spec-ngram-mod-n-min 48"
        # "--spec-ngram-mod-n-max 64"
        "--no-ui"
      ];
      # ttl = 600;
    };
  };
}
