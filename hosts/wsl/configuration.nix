# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

{
  config,
  lib,
  pkgs,
  unstable-pkgs,
  ...
}:

let
  llama-cpp-cuda = unstable-pkgs.llama-cpp.override {
    blasSupport = true;
    cudaSupport = true;
    rocmSupport = false;
    metalSupport = false;
  };
  modelDir = "/var/lib/llama-models";
in
{
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

  services.dbus.enable = true;

  wsl.useWindowsDriver = true;
  hardware.graphics.enable = true;

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  disabledModules = [ "services/misc/ollama.nix" ];
  imports = [ "${unstable-pkgs.path}/nixos/modules/services/misc/ollama.nix" ];
  services.ollama = {
    enable = false;
    package = unstable-pkgs.ollama-cuda;
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "32768";
    };
  };

  users.groups.llama = { };

  systemd.tmpfiles.rules = [
    "d ${modelDir} 0775 root llama -"
  ];

  systemd.services.llama-swap = {
    serviceConfig.ReadOnlyPaths = [
      modelDir
      "/usr/lib/wsl/lib"
    ];
    environment.LD_LIBRARY_PATH = "/usr/lib/wsl/lib";
  };

  services.llama-swap = {
    enable = true;
    # The 'settings' follow the llama-swap YAML structure
    # NB default port = 8080
    settings = {
      models = {
        "gemma-4-e4b" = {
          # ${PORT} is automatically assigned by llama-swap
          cmd = "${llama-cpp-cuda}/bin/llama-server --model ${modelDir}/gemma-4-E4B-it-UD-Q8_K_XL.gguf --port \${PORT} --n-gpu-layers 100 --flash-attn on --ctx-size 131072";
          ttl = 600; # Shut down after 10 mins (600s) of idle to save VRAM
        };
        # hf download unsloth/gemma-4-26B-A4B-it-GGUF --local-dir /var/lib/llama-models/unsloth/gemma-4-26B-A4B-it-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*"
        "gemma-4-26b" = {
          # https://unsloth.ai/docs/models/gemma-4
          cmd = "${llama-cpp-cuda}/bin/llama-server --model ${modelDir}/unsloth/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf --port \${PORT} --temp 1.0 --top-p 0.95 --top-k 64 --ctx-size 131072";
          ttl = 600; # Shut down after 10 mins (600s) of idle to save VRAM
        };
        "qwen-3-5-9b" = {
          # ${PORT} is automatically assigned by llama-swap
          cmd = "${llama-cpp-cuda}/bin/llama-server --model ${modelDir}/Qwen3.5-9B-UD-Q6_K_XL.gguf --port \${PORT} --n-gpu-layers 100 --flash-attn on --ctx-size 131072";
          ttl = 600; # Shut down after 10 mins (600s) of idle to save VRAM
        };
        # hf download unsloth/Qwen3.6-35B-A3B-GGUF --local-dir /var/lib/llama-models/unsloth/Qwen3.6-35B-A3B-GGUF --include "*mmproj-F16*" --include "*UD-Q4_K_XL*"
        "qwen-3-6-35b" = {
          #cmd = "${llama-cpp-cuda}/bin/llama-server --model ${modelDir}/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf --port \${PORT} -ngl 999 --n-cpu-moe 35 --no-mmap --ctx-size 131072";
          # https://unsloth.ai/docs/models/qwen3.6
          cmd = "${llama-cpp-cuda}/bin/llama-server --model ${modelDir}/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf --port \${PORT} --temp 0.6 --top-p 0.95 --top-k 20 --presence-penalty 0.0 --ctx-size 131072";
          ttl = 600; # Shut down after 10 mins (600s) of idle to save VRAM
        };
      };
    };
  };

  services.flatpak.enable = true;
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";

  virtualisation.docker.enable = true;
  virtualisation.podman = {
    enable = true;
    # Ensure containers can talk to each other via DNS (essential for Compose)
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.sessionVariables = {
    LD_LIBRARY_PATH = [
      # https://yomaq.github.io/posts/nvidia-on-nixos-wsl-ollama-up-24-7-on-your-gaming-pc/
      "/usr/lib/wsl/lib"
    ];
  };

  environment.systemPackages =
    (with pkgs; [
      xdg-utils
      vim
      wget
      nixfmt-rfc-style
      usbutils
      kmod # for modprobe, required by WSL usbipd
      docker-compose # This is V2 (the Go version) - podman needs it in PATH
      hello-script
      goodbye-script
    ])
    ++ [ llama-cpp-cuda ];

  # required for example for esp32-rs to sandbox the pre-built rustc/rustdoc binaries
  security.wrappers = {
    # Low-level unprivileged sandboxing tool, see <https://github.com/containers/bubblewrap>.
    bwrap = {
      owner = "root";
      group = "root";
      source = "${pkgs.bubblewrap}/bin/bwrap";
      setuid = true;
    };
  };

  programs.git.enable = true;
  # VSCode remoting requires dynamic linking to ld-linux
  programs.nix-ld.enable = true;

  users.users.itcalde = {
    linger = true;
    isNormalUser = true;
    uid = 1001;
    home = "/home/itcalde";
    description = "Iain Calder";
    extraGroups = [
      "wheel"
      "dialout"
      "docker"
      "podman"
      "llama"
    ];
    # openssh.authorizedKeys.keys  = [ "ssh-dss AAAAB3Nza... alice@foobar" ];
  };

  # this avoids warnings about flake configuration options like substituters
  nix.settings.trusted-users = [
    "root"
    "itcalde"
  ];
}
