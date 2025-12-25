{ nixpkgs, system, pkgs, unstable-pkgs }:
extraArgs:
let
  baseArgs = {
    inherit system;
    specialArgs = {
      inherit unstable-pkgs;
    };
    modules = [
      "${nixpkgs}/nixos/modules/virtualisation/hyperv-image.nix"
      {
        nixpkgs.pkgs = pkgs;
        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
      }
      {
        virtualisation.diskSize = 20 * 1024; # 20GB
      }
      ../hosts/hyperv-vm/configuration.nix
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
