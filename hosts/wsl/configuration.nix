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

{
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

  wsl.useWindowsDriver = true;
  hardware.graphics.enable = true;

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  services.dbus.enable = true;
  services.ollama = {
    enable = true;
    acceleration = "cuda";
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "16384";
    };
  };

  services.open-webui = {
    enable = true;
    port = 8800;
  };

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

  environment.systemPackages = with pkgs; [
    vim
    wget
    nixfmt-rfc-style
    usbutils
    kmod # for modprobe, required by WSL usbipd
    pkgs.docker-compose # This is V2 (the Go version) - podman needs it in PATH
    hello-script
    goodbye-script
  ];

  programs.git.enable = true;
  # VSCode remoting requires dynamic linking to ld-linux
  programs.nix-ld.enable = true;

  users.users.itcalde = {
    isNormalUser = true;
    uid = 1001;
    home = "/home/itcalde";
    description = "Iain Calder";
    extraGroups = [
      "wheel"
      "dialout"
      "docker"
      "podman"
    ];
    # openssh.authorizedKeys.keys  = [ "ssh-dss AAAAB3Nza... alice@foobar" ];
  };
}
