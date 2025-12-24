{ config, ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:icalder/nixos#${config.networking.hostName}"; # Point to your central repo
    dates = "02:00"; # Run at 2 AM
    randomizedDelaySec = "45min"; # Avoid all Pis hitting GitHub at once
    flags = [
      "--refresh" # Force fetching latest flake info
    ];
    allowReboot = true; # Optional: reboot for kernel updates
  };
}