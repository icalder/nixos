{ config, ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:icalder/nixos#${config.networking.hostName}"; # Point to your central repo
    dates = "Sun 02:00"; # Run at 2 AM on Sunday, after CI has updated flake.lock
    randomizedDelaySec = "45min"; # Avoid all Pis hitting GitHub at once
    flags = [
      "--refresh" # Force fetching latest flake info
    ];
    allowReboot = true; # Optional: reboot for kernel updates
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d"; # Deletes generations older than 2 weeks
  };
}
