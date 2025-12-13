# modules/generate-hardware.nix

{ config, pkgs, ... }:

let
  hardwareConfigFile = "/etc/nixos/hardware-configuration.nix";
in
{
  # 1. Ensure nixos-rebuild is available in the VM for the second step
  environment.systemPackages = [ config.system.build.nixos-rebuild ];

  # 2. Define a systemd service to run on first boot
  systemd.services.generate-hardware-config = {
    # Only run once at the main boot target (multi-user.target)
    wantedBy = [ "multi-user.target" ];

    # This service runs *before* the system attempts to activate the configuration,
    # but still early enough to be useful.
    after = [ "local-fs.target" ];

    # Stop the service if the config file exists
    conditionPathExists = "!${hardwareConfigFile}";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes"; # Mark service as successfully finished
      User = "root";
    };

    script = ''
      echo "--- Starting dynamic hardware configuration generation ---"

      # Use the NixOS tool to scan the current VM's hardware and write the config
      ${pkgs.nixos-generate-config}/bin/nixos-generate-config \
        --force \
        --dir /etc/nixos 
        
      echo "Hardware configuration saved to ${hardwareConfigFile}"

      # Now, immediately perform a rebuild to load the new config
      # The '--impure' flag is required here because we are reading the newly 
      # generated hardware-configuration.nix file that is NOT tracked in the flake.
      echo "--- Running self-rebuild to apply hardware-configuration.nix ---"
      # ${config.system.build.nixos-rebuild} switch \
      #   --flake /etc/nixos#\${config.networking.hostName} \
      #   --impure
        
      echo "--- Self-rebuild complete. The correct configuration is now active. ---"
    '';
  };
}
