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

  # This card swapfile alone is not enough. The last run that completed
  # (Sun 2026-10-25) reported 176.4 MiB memory peak and 774.7 MiB swap peak --
  # about three quarters of the whole swapfile -- on a machine with 375 MiB of
  # RAM, and that same run wrote 4.3 GB to the card it was swapping onto.
  swapDevices = [
    {
      device = "/swapfile";
      size = 1024; # Size in MB (1GB)
    }
  ];

  # Give reclaim something faster than the card to put anonymous memory in.
  # zramSwap's priority is above the -2 this swapfile gets, so the hot part of
  # the spill lands in RAM while the card keeps its role as the slow backstop:
  # 774.7 MiB of peak spill does not fit in a 120 MiB device, so the swapfile
  # has to stay.
  #
  # Deliberately not alarmpi's numbers. modules/sd-card-tuning.nix picks
  # swappiness=180 and page-cluster=0 for any host with zram enabled, and both
  # assume zram is the only swap device: 180 means "swap is cheaper than page
  # cache", and page-cluster=0 reads 4 KiB per fault because zram access is
  # cheap and near-random. Neither holds while a card swapfile still carries
  # most of the spill -- there small reads are worse than bulk reads. So: small
  # device (ALARMPI-ISSUES.md §8.8 asks for 30-40% here, not alarmpi's 75%),
  # page-cluster kept at the card-friendly default, swappiness raised but not as
  # far. 100 is a starting point, not a measured optimum: alarmpi's runs still
  # spill past its own device (744.8M swap peak against a 648M device, §8.2), so
  # the card is in the swap path on both boxes and only 3a's numbers can say
  # whether 100 was the right opening bid. Re-measure after the next run:
  #
  #     zramctl; swapon --show; cat /proc/pressure/memory
  #     grep -E 'MemFree|MemAvailable|SwapCached' /proc/meminfo
  #     journalctl -u nixos-upgrade.service | grep Consumed
  #     awk '/zone DMA/,0' /proc/zoneinfo | grep -m4 -E 'min|low|high'
  zramSwap = {
    enable = true;
    memoryPercent = 32; # ~120 MiB of device on 375 MiB of RAM
  };

  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "vm.page-cluster" = 3;
  };

  # 65536 is the sd-card-tuning default, sized for a 1 GiB board. On 375 MiB it
  # is 17% of RAM held permanently below the low watermark: measured live, the
  # zone watermarks were min 64 / low 80 / high 96 MiB against 94 MiB of
  # MemAvailable. 16384 is 4.3% of RAM, which keeps the module's intent (more
  # reserve than the kernel would pick: alarmpi's default was 22528 at 865 MiB,
  # ALARMPI-ISSUES.md §8.2) at a scale this board can pay for. Not a measured
  # optimum -- the watermark check after the next deploy says whether.
  # NIXOS-3A-ISSUES.md §6.1 has the numbers.
  sdCardTuning.minFreeKiB = 16384;

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

  # This host builds its own upgrades: nixos-upgrade.timer fires weekly and the
  # build runs here, not on the x86 box. With 375 MiB and no zram, one compiler
  # thread per derivation is the difference between a slow build and a box that
  # wedges in uninterruptible sleep. lowRamRebuild used to supply this; it is now
  # opt-in for alarmpi only, so the serialisation is stated here instead. The
  # cgroup ceilings that module also sets are deliberately not reproduced: on a
  # 375 MiB machine they sat above the machine's own RAM and protected nothing.
  nix.settings.max-jobs = 1;
  nix.settings.cores = 1;

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

  # The whole ADS-B feeder chain (dump1090-fa, its nginx map, fr24feed and the
  # adsbexchange guest) lives in modules/adsb-feeder.nix, shared with alarmpi.
  # This box is the primary feeder; set the same flag to true on alarmpi and to
  # false here to fail over.
  adsbFeeder.enable = true;

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
