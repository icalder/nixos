{
  description = "Goose CLI v1.26.1";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkGoose = pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          rustyV8LibName = {
            "x86_64-linux" = "librusty_v8_release_x86_64-unknown-linux-gnu.a.gz";
            "aarch64-linux" = "librusty_v8_release_aarch64-unknown-linux-gnu.a.gz";
            "x86_64-darwin" = "librusty_v8_release_x86_64-apple-darwin.a.gz";
            "aarch64-darwin" = "librusty_v8_release_aarch64-apple-darwin.a.gz";
          };
          rustyV8Hashes = {
            "x86_64-linux" = "sha256-chV1PAx40UH3Ute5k3lLrgfhih39Rm3KqE+mTna6ysE=";
            "aarch64-linux" = nixpkgs.lib.fakeHash;
            "x86_64-darwin" = nixpkgs.lib.fakeHash;
            "aarch64-darwin" = nixpkgs.lib.fakeHash;
          };
          librusty_v8 = pkgs.fetchurl {
            url = "https://github.com/denoland/rusty_v8/releases/download/v145.0.0/${rustyV8LibName.${system}}";
            hash = rustyV8Hashes.${system};
          };
        in
        pkgs.goose-cli.overrideAttrs (oldAttrs: rec {
          version = "1.26.1";
          src = pkgs.fetchFromGitHub {
            owner = "block";
            repo = "goose";
            tag = "v${version}";
            hash = "sha256-2qsRLeBXAJzaOEVarU5LGQp9iooPsYq/+vrMx5Mr2Gw=";
          };
          cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
            inherit src;
            hash = "sha256-XHjOne43aCu6CkLaAF12TOcmP4TxSACu8Juxio3Td4k=";
          };
          nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
            pkgs.rustPlatform.bindgenHook
            pkgs.cmake
          ];
          doCheck = false;
          RUSTY_V8_ARCHIVE = librusty_v8;
        });
    in
    {
      packages = forAllSystems (system: {
        default = mkGoose nixpkgs.legacyPackages.${system};
      });

      overlays.default = final: prev: {
        goose-cli = mkGoose prev;
      };
    };
}
