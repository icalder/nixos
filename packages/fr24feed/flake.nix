{
  description = "Flightradar24 Feeder package and NixOS module";

  inputs = {
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      # List of supported systems from fr24feed.nix
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Helper function to generate outputs for each supported system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # Define the 'fr24feed' package for each supported system
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          fr24feed = pkgs.callPackage ./fr24feed.nix { };
        }
      );

      # The NixOS module is system-agnostic
      nixosModules.fr24feed = import ./module.nix;

      # TODO https://discourse.nixos.org/t/trying-to-contribute-to-nixpkgs-but-only-buildfhsenv-works-for-binary/36579/2

      overlays.default = final: prev: {
        fr24feed = self.packages.${final.stdenv.hostPlatform.system}.fr24feed;
      };
    };
}
