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

  services.dbus.enable = true;

  services.udev.enable = true;
  # Define the custom rule for the Pico Debug Probe
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", ATTR{idProduct}=="000c", GROUP="dialout", MODE="0660"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="000c", GROUP="dialout", MODE="0660"
  '';

  wsl.useWindowsDriver = true;
  hardware.graphics.enable = true;

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  users.groups.llama = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/llama-models 0775 root llama -"
    # Anchor for the sandbox project bind: WSL interop maps the CWD to
    # \\wsl.localhost\NixOS\app, so /app must exist on the host.
    "d /app 0755 root root -"
  ];

  systemd.services.llama-swap = {
    serviceConfig.ReadOnlyPaths = [
      "/var/lib/llama-models"
      "/usr/lib/wsl/lib"
    ];
    environment.LD_LIBRARY_PATH = "/usr/lib/wsl/lib";
  };

  # services.llama-swap = {
  #   enable = false;
  #   package = unstable-pkgs.llama-swap;
  #   listenAddress = "0.0.0.0";
  #   settings = llama-swap-settings;
  # };

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

  # The in-cluster zot registry (infra/zot-registry in the k3s repo) serves
  # plain HTTP on the LAN, so both engines have to allow it without TLS.
  virtualisation.docker.daemon.settings = {
    insecure-registries = [
      "192.168.1.48:5000"
      "192.168.1.51:5000"
    ];
  };

  environment.etc."containers/registries.conf.d/10-lan-registry.conf".text = ''
    [[registry]]
    prefix = "192.168.1.48:5000"
    location = "192.168.1.48:5000"
    insecure = true

    [[registry]]
    prefix = "192.168.1.51:5000"
    location = "192.168.1.51:5000"
    insecure = true
  '';

  # Include XDG ~/.local/bin in PATH, so that scripts installed there are available in the shell
  environment.localBinInPath = true;

  environment.sessionVariables = {
    LD_LIBRARY_PATH = [
      "/usr/lib/wsl/lib"
    ];
  };

  environment.systemPackages = (
    with pkgs;
    [
      xdg-utils
      vim
      wget
      nixfmt
      usbutils
      kmod # for modprobe, required by WSL usbipd
      docker-compose # This is V2 (the Go version) - podman needs it in PATH
      hello-script
      goodbye-script
      bubblewrap # sandbox's runtime; also on PATH for other devshells
      agent-sandbox # provides `sandbox` and `sandbox-verify`
    ]
  );
  # ++ [ llama-cpp-cuda ];

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
