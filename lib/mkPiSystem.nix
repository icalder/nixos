{
  nixpkgs,
  system,
  pkgs,
  unstable-pkgs,
  agenix,
}:
extraArgs:
let
  baseArgs = {
    inherit system;
    specialArgs = {
      inherit unstable-pkgs;
    };
    modules = [
      "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
      {
        # Tells Nix to cross-compile from your build host
        nixpkgs.buildPlatform = "x86_64-linux";
        nixpkgs.hostPlatform = "aarch64-linux";
        nixpkgs.pkgs = pkgs;
        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
        boot.kernel.sysctl = {
          "kernel.dmesg_restrict" = 0;
        };

        # profiles/base.nix turns ZFS on for every nixosSystem, which loads the
        # zfs and spl modules and runs zed on a board that has no pools and
        # cannot gain one. The set form with mkForce is how nixpkgs says to
        # switch a single filesystem back off without disturbing the rest.
        boot.supportedFilesystems = {
          zfs = pkgs.lib.mkForce false;
        };
      }
      agenix.nixosModules.default
      ../modules/autoupgrade.nix
      ../modules/low-ram-rebuild.nix
      ../modules/sd-card-tuning.nix
      # modules/adsb-feeder.nix is deliberately NOT imported here. It mentions
      # services.fr24feed, an option that exists only where flake.nix also adds
      # fr24feed.nixosModules.fr24feed, i.e. alarmpi and nixos-3a. Importing it
      # for every Pi breaks the hosts that lack that module: lib.mkIf false
      # still yields { _type = "if"; content = ...; }, and the module system's
      # undefined-option check walks the paths a block mentions whether or not
      # its condition holds, so rpi4-1 fails to evaluate even with the feeder
      # switched off. Hosts that feed import it themselves.
    ];
  };

  # combine modules, don't replace
  combinedModules = baseArgs.modules ++ (extraArgs.modules or [ ]);

  # merge extraArgs over baseArgs, but keep combined modules
  finalArgs = (baseArgs // extraArgs) // {
    modules = combinedModules;
  };
in
nixpkgs.lib.nixosSystem finalArgs
