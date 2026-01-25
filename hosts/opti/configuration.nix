# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  unstable-pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    "${unstable-pkgs.path}/nixos/modules/services/misc/ollama.nix"
  ];

  # Enable zRAM swap
  zramSwap = {
    enable = true;
    algorithm = "zstd"; # Same as modern Arch defaults
    memoryPercent = 50; # Max size of zram device (e.g., 4GB on 8GB RAM)
    priority = 100; # Ensures it is used before any disk-based swap
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "nfs" ];
  # Enable Intel GPU firmware loading for extra video acceleration
  boot.kernelParams = [
    "i915.enable_guc=3"
    "reboot=pci"
    "usbcore.quirks=0bda:9210:k"
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # Hardware video acceleration
      vulkan-loader
      vulkan-validation-layers
    ];
  };

  disabledModules = [ "services/misc/ollama.nix" ];
  services.ollama = {
    enable = true;
    package = unstable-pkgs.ollama-vulkan;
  };

  age.secrets = {
    itcalde.file = ../../secrets/itcalde.age;
  };

  # DHCP IPV4 options set here to wait for an address before continuing boot
  # otherwise k3s etcd can fail with IP4/IP6 mismatch
  networking = {
    hostName = "opti";

    useNetworkd = true; # Enable systemd-networkd
    useDHCP = false; # Disable global scripted DHCP
    dhcpcd.enable = false; # Explicitly turn off dhcpcd
  };

  systemd.network = {
    enable = true;
    networks."10-lan" = {
      # Matches any ethernet interface (e.g., eno1, enp2s0)
      matchConfig.Name = "en*";

      networkConfig = {
        DHCP = "yes"; # Get both IPv4 and IPv6 via DHCP/RA
        IPv6PrivacyExtensions = "no"; # Keep a stable IPv6 address
      };

      linkConfig = {
        RequiredForOnline = "routable";
        # The "Secret Sauce" for k3s
        RequiredFamilyForOnline = "ipv4";
      };
    };
  };

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  console.keyMap = "uk";
  # Configure keymap for X11 (and Wayland/WLM usually inherit this)
  # services.xserver.xkb.layout = "gb";

  # Means users cannot be added or removed using 'useradd' or 'userdel', passwords are managed via agenix only
  users.mutableUsers = false;
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.itcalde = {
    isNormalUser = true;
    description = "Iain Calder";
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      "plugdev" # USB device access
      "dialout" # USB serial port access
    ];
    # generate with 'mkpasswd'
    hashedPasswordFile = config.age.secrets.itcalde.path;
    packages = with pkgs; [
      # tree
      cowsay
      direnv
      nix-direnv
    ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAuSEf//2a4x+eTqtmhNfQuTJ0vMmGSq5En6FAsxTUYPauzXmH59sG/SRryZpsQq+nGEZLfQ1R2mAq8M71ZJPCCOoYTN3yxdyCpjlodva7+5PpTvE9KQmThlm9Y+RL8dVq413uEwlav2kLa0RBsx10i2vcVMJ1FKno7mQz5/u6G3CXt++YJoPWoNVPIxIIefUot2kj9b2b7wf4EuWPOr5noH41N/E67/1OqfItqaaSGgP9ky9qCKdrI8J1ukhSDsvxmlF/f0kgpl6KVAEpx0/qfVsBoR5BBuNJg8gcWUso0Y92D+7sWULKXZV69Ka4uJ93HqCrKkd1iQpGOO/n6VCRkQ== itcalde@wombatzone.localdomain"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
  # this allows remote nixos-rebuild via ssh to trust binary packages copied over by my user
  nix.settings.trusted-users = [
    "root"
    "itcalde"
  ];
  nix.channel.enable = false;

  programs.git.enable = true;
  programs.nix-ld.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    intel-gpu-tools # Includes intel_gpu_top to monitor usage
  ];
  # Configure nix-direnv globally (system-wide)
  # This section ensures that the direnvrc is configured correctly for *all* users
  # who use direnv, by making the nix-direnv config available globally.
  # This is the NixOS way to manage the global configuration.
  programs.direnv.nix-direnv.enable = true;
  programs.bash.interactiveShellInit = ''
    # Only run the hook if the 'direnv' command is available (i.e., installed for the user)
    if command -v direnv >/dev/null 2>&1; then
      eval "$(direnv hook bash)"
    fi
  '';

  # Force k3s to respect the network-online target
  systemd.services.k3s = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };
  services.k3s = {
    enable = true;
    role = "server";
    token = "20orchardrd";
    clusterInit = true;
    extraFlags = toString [
      "--flannel-iface=enp1s0" # Bind to the physical link, not an IP
      "--node-name=opti" # Explicitly pin the name
      "--kubelet-arg=node-ip=0.0.0.0" # Tell kubelet to be IP-agnostic
      "--write-kubeconfig-mode 644"
      "--default-local-storage-path /data"
      "--node-label \"nats-host=true\""
      "--node-label \"postgresql-host=true\""
    ];
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?
}
