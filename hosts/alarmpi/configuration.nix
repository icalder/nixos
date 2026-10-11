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
  imports = [
    # Owns dump1090-fa, its nginx map, fr24feed and the adsbexchange guest
    # behind a single adsbFeeder.enable switch. Imported per host rather than
    # by lib/mkPiSystem.nix, because the module needs the fr24feed module that
    # flake.nix only supplies to hosts that actually feed.
    ../../modules/adsb-feeder.nix
  ];

  boot.kernelParams = [
    "snd_usb_audio.index=2"
  ];

  swapDevices = [
    {
      device = "/swapfile";
      # Disk swapback stays only as a rare last resort. zramSwap has a higher
      # priority, so build memory pressure is absorbed in RAM first instead of
      # thrashing swap on the SD card (which triggered the mmc stall / hang).
      size = 1024; # Size in MB (1GB)
    }
  ];

  # In-RAM compressed swap instead of relying on the SD-backed /swapfile.
  # A nix upgrade runs builds that spike RAM on this 865 MiB Pi; with zram
  # first, that pressure is handled in RAM rather than generating heavy disk
  # I/O on the SD card during updates.
  zramSwap = {
    enable = true;
    memoryPercent = 75; # cap the device at 3/4 of RAM; zstd keeps effective cap high
  };

  # Peak observed for a weekly nixos-upgrade: 649 MiB RSS and 962 MiB swap, on
  # a machine with 865 MiB total. Those numbers are survivable on their own;
  # what killed the box was doing it while the SD card was also absorbing up to
  # 7.9 GiB of writes. Cap the build side so it cannot outgrow the machine.
  lowRamRebuild = {
    enable = true;
    throttleAtMiB = 448;
    killAtMiB = 576;
    swapBudgetMiB = 768;
    pauseBelow = 224 * 1024 * 1024;
    resumeAt = 448 * 1024 * 1024;
  };

  # No runtime watchdog, for now. The weekly hang is a userspace I/O stall, so
  # nothing resets the board and it sat unreachable for hours until the power
  # was pulled, and /dev/watchdog0 looks like an easy fix. It is available --
  # systemd already arms this same device with a 10min timeout on every reboot
  # (RebootWatchdogSec default), so the BCM2835 timer is not the ~16s limit I
  # first assumed from max_timeout=0. RuntimeWatchdogSec is left off because a
  # 15min stall rebooting the box mid-`nixos-rebuild switch` is how the card
  # gets corrupted. Revisit once a real run has been observed under the new
  # memory ceilings. See ALARMPI-ISSUES.md, 8.1.

  age.secrets = {
    itcalde.file = ../../secrets/itcalde.age;
    "wireless.conf" = {
      file = ../../secrets/wireless.conf.age;
      owner = "root";
      group = "wpa_supplicant";
      mode = "0440";
    };
  };

  # See https://github.com/mcdonc/nixos-pi-zero-2/blob/main/common.nix for more options

  networking.hostName = "alarmpi"; # Define your hostname.
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

  # Cap concurrent build jobs so peak RAM and concurrent disk I/O stay
  # manageable during upgrades on this low-RAM Pi. See modules/low-ram-rebuild.nix
  # for the full set of limits (jobs, cores, memory ceilings, I/O priority).

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
    alsa-utils
    ffmpeg
    ubc125
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

  # This is a test of packaging a running a completely custom system service.
  # It listens on port 3000 and responds with "Hello, World!" to any HTTP request.
  # It can be tested by running `curl http://localhost:3000/` after starting the service.
  systemd.services.hello-world-server = {
    description = "Hello World Server";
    enable = true;

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

  # dump1090-fa, its nginx map, fr24feed and the adsbexchange guest all live in
  # modules/adsb-feeder.nix, shared with nixos-3a. This box is the standby
  # feeder, so the switch is off; flip it to true here and to false on nixos-3a
  # to fail over. The guest costs roughly 60 MiB of resident RAM, which this
  # machine cannot spare while it is rebuilding.
  adsbFeeder.enable = false;

  services.ubc125 = {
    enable = true;
    # listenAddress = "0.0.0.0:50051";  # default
    # device = "/dev/ttyACM0";          # default: auto-detect by USB id
    # audioDevice = "hw:2";             # default: the Pi's USB mic
    declick = true; # default: false, experimental audio de-clicker
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
  system.stateVersion = "25.11"; # Did you read the comment?

}
