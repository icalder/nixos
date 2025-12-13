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
            version = "0.1.0";

            src = pkgs.fetchurl {
              url = "https://github.com/icalder/adsbexchange/releases/download/v${version}/rootfs.tar.gz";
              sha256 = "sha256:46541f723673322b8fa30c5edd08b6211f21d1f57a5de0582101b7d5eae92feb"; # Preserving user's hash
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
