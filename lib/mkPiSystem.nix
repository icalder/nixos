{ nixpkgs, system, pkgs, unstable-pkgs, agenix }:
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
      }
      agenix.nixosModules.default
      ../modules/autoupgrade.nix
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
