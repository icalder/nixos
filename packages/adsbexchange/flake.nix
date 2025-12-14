{
  description = "A flake for the ADSBExchange filesystem image";

  inputs = {
  };

  outputs =
    { self, nixpkgs }:
    let
      # List of supported systems to expose the package on
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Helper to generate outputs for each supported system
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import nixpkgs { inherit system; };
          }
        );
    in
    {
      # Expose the package for different systems
      packages = forAllSystems (
        { pkgs }:
        {
          default = pkgs.stdenv.mkDerivation rec {
            pname = "adsbexchange-fs";
            version = "0.1.0-bookworm";

            src = pkgs.fetchurl {
              url = "https://github.com/icalder/adsbexchange/releases/download/v${version}/rootfs.tar.gz";
              sha256 = "sha256:0f9492f4da7eee9e41cc3623f76884a55b572ae39f6d60432711f31ccbcacc30"; # Preserving user's hash
            };

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out
              cp $src $out/rootfs.tar.gz
            '';
          };
        }
      );

      # Overlay to make the package available as `pkgs.adsbexchange-fs`
      overlays.default = final: prev: {
        adsbexchange-fs = self.packages.${prev.stdenv.hostPlatform.system}.default;
      };
    };
}
