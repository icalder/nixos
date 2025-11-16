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

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    wget
    nixfmt-rfc-style
    usbutils
    kmod # for modprobe, required by WSL usbipd
    hello-script
    goodbye-script
    hello-world-server
  ];

  systemd.services.hello-world-server = {
    description = "Hello World Server";
    enable = false;

    # This ensures the service is started at boot
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    # Configuration for the service itself
    serviceConfig = {
      # It's good practice to run services as a non-privileged user
      User = "itcalde";

      # The command to start the service.
      ExecStart = "${pkgs.hello-world-server}/bin/hello-world-server";

      # Automatically restart the service if it fails
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  programs.git.enable = true;
  # VSCode remoting requires dynamic linking to ld-linux
  programs.nix-ld.enable = true;

  users.users.itcalde = {
    isNormalUser = true;
    home = "/home/itcalde";
    description = "Iain Calder";
    extraGroups = [
      "wheel"
      "dialout"
      "docker"
    ];
    # openssh.authorizedKeys.keys  = [ "ssh-dss AAAAB3Nza... alice@foobar" ];
  };
}
