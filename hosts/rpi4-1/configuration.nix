# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # TODO import hardware-configuration.nix
  # imports = [ ./hardware-configuration.nix ];

  # Enable zRAM swap
  zramSwap = {
    enable = true;
    algorithm = "zstd"; # Same as modern Arch defaults
    memoryPercent = 50; # Max size of zram device (e.g., 4GB on 8GB RAM)
    priority = 100; # Ensures it is used before any disk-based swap
  };

  boot.supportedFilesystems = [ "nfs" ];

  age.secrets = {
    itcalde.file = ../../secrets/itcalde.age;
  };

  networking.hostName = "rpi4-1";
  time.timeZone = "Europe/London";

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

  services.k3s = {
    enable = false;
    role = "agent";
    token = "20orchardrd";
    serverAddr = "https://k3sserver:6443";
  };
  systemd.tmpfiles.rules = [
    "d /data 0755 root root -"
  ];

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
