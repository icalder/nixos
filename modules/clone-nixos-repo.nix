# A function that returns a NixOS module for cloning the nixos config repo.
# It takes the username as an argument.
user:
{ config, pkgs, ... }: {
  environment.systemPackages = [ pkgs.git ];
  systemd.services.clone-nixos-repo = {
    description = "Clone nixos configuration repository";
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      # This will only run if the directory does not exist.
      ConditionPathExists = "!${config.users.users.${user}.home}/nixos/.git";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    serviceConfig = {
      Type = "oneshot";
      User = user;
      ExecStart = "${pkgs.git}/bin/git clone https://github.com/icalder/nixos/ ${config.users.users.${user}.home}/nixos";
    };
  };
}
