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
  # imports = [
  #   # Include the results of the hardware scan.
  #   ./hardware-configuration.nix
  # ];

  swapDevices = [
    {
      device = "/swapfile";
      size = 1024; # Size in MB (1GB)
    }
  ];

  age.secrets = {
    itcalde.file = ../../secrets/itcalde.age;
    "wireless.conf".file = ../../secrets/wireless.conf.age;
    fr24key.file = ../../secrets/fr24key.age;
  };

  # See https://github.com/mcdonc/nixos-pi-zero-2/blob/main/common.nix for more options

  # hardware.pulseaudio.enable = true;

  networking.hostName = "nixos-3a"; # Define your hostname.
  # See https://mynixos.com/nixpkgs/options/hardware for all hardware options.
  hardware = {
    enableRedistributableFirmware = lib.mkForce false; # Keep this to make sure wifi works
    firmware = [ pkgs.raspberrypiWirelessFirmware ];
    rtl-sdr.enable = true;
  };

  networking = {
    useDHCP = true;
    wireless = {
      enable = true;
      interfaces = [ "wlan0" ];
      secretsFile = config.age.secrets."wireless.conf".path;
      networks = {
        langwell.pskRaw = "ext:psk";
      };
    };
  };

  # Set your time zone.
  time.timeZone = "Europe/London";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.itcalde = {
    isNormalUser = true;
    description = "Iain Calder";
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      "plugdev" # USB device access
      "audio" # Audio device access
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

  # programs.firefox.enable = true;
  programs.git.enable = true;
  programs.nix-ld.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    rtl-sdr-librtlsdr
    dump1090-fa
    fr24feed
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

  services.dump1090-fa.enable = true;
  services.dump1090-fa.extraArgs = [
    "--quiet"
    "--adaptive-range"
    "--lat"
    "51.87696"
    "--lon"
    "-2.20132"
  ];
  #services.dump1090-fa.extraArgs = [ "--quiet" "--gain -10" ];
  systemd.services.dump1090-fa.serviceConfig = {
    PrivateNetwork = lib.mkForce false;
  };

  services.nginx = {
    enable = true;
    virtualHosts."default" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
      ];
      locations."/dump1090" = {
        return = "301 /dump1090/";
      };
      locations."/dump1090/data/" = {
        alias = "/run/dump1090-fa/";
        extraConfig = "expires off;";
      };
      locations."/dump1090/" = {
        alias = "${pkgs.dump1090-fa}/share/dump1090/";
        index = "index.html";
      };
    };
  };

  # Prepare adsbexchange machine image during system activation.
  # Has to be done here because ExecStartPre cannnot run mknod on /var/lib/machines.
  system.activationScripts.prepare-adsbexchange-machine = {
    deps = [
      "users"
      "groups"
    ]; # Ensure users/groups are set up first
    text = ''
      IMAGE_DEST="/var/lib/machines/adsbexchange"
      if [ ! -d "$IMAGE_DEST" ]; then
        echo "Deploying adsbexchange machine image during system activation..."
        mkdir -p "$IMAGE_DEST"
        ${pkgs.gnutar}/bin/tar --use-compress-program=${pkgs.gzip}/bin/gzip -xpf ${pkgs.adsbexchange-fs}/rootfs.tar.gz -C "$IMAGE_DEST" --numeric-owner --xattrs --xattrs-include='*'
      fi
    '';
  };

  systemd.targets.machines.enable = true;
  systemd.nspawn.adsbexchange = {
    enable = true;
    execConfig = {
      Boot = true;
    };
    networkConfig = {
      VirtualEthernet = "no";
    };
    filesConfig = {
      BindReadOnly = [ "/etc/resolv.conf:/etc/resolv.conf" ];
    };
  };
  systemd.services."systemd-nspawn@adsbexchange" = {
    enable = true;
    wantedBy = [ "machines.target" ];
    # https://mynixos.com/nixpkgs/option/systemd.mounts.*.overrideStrategy
    overrideStrategy = "asDropin";
  };

  services.fr24feed = {
    enable = true;
    fr24key = config.age.secrets.fr24key.path;
  };

  # environment.etc."nixos" = {
  #   source = ../../.;
  # };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

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
  system.stateVersion = "25.05"; # Did you read the comment?

}
