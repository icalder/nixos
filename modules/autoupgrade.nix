{ config, ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:icalder/nixos#${config.networking.hostName}"; # Point to your central repo
    dates = "Sun 02:00"; # Run at 2 AM on Sunday, after CI has updated flake.lock
    randomizedDelaySec = "45min"; # Avoid all Pis hitting GitHub at once
    flags = [
      "--refresh" # Force fetching latest flake info
      "--accept-flake-config" # Accept configuration from the flake, e.g. substituters
    ];
    allowReboot = true; # Optional: reboot for kernel updates
  };

  # Keep garbage collection out of the upgrade window. Both are write-heavy, and
  # on an SD card they compete for the same queue; collecting garbage while a
  # rebuild is unpacking a closure is how a Sunday night turns into a stalled
  # card. Monday midnight is ~22h clear of the Sunday upgrade, and the delay
  # stops every host in the fleet trimming at the same moment.
  nix.gc = {
    automatic = true;
    dates = "Mon 00:00";
    options = "--delete-older-than 14d"; # Deletes generations older than 2 weeks
    randomizedDelaySec = "90min";
  };
}
