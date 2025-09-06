# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # include NixOS-WSL modules
    <nixos-wsl/modules>
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  wsl.enable = true;
  wsl.defaultUser = "itcalde";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    wget
    nixfmt-rfc-style
    usbutils
    kmod # for modprobe, required by WSL usbipd
  ];

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
