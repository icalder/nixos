{
  description = "Goose CLI v1.38.0 — fetched from GitHub release tarballs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      version = "1.38.0";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Map Nix platform + variant to GitHub release tarball name
      assetNameFor =
        {
          system,
          variant ? "gnu",
        }:
        let
          host = nixpkgs.legacyPackages.${system}.stdenv.hostPlatform;
          arch =
            if host.isAarch64 then
              "aarch64"
            else if host.isx86_64 then
              "x86_64"
            else
              null;

          # Variant determines the libc, not the nixpkgs stdenv
          targetTriple =
            if variant == "musl" then
              "unknown-linux-musl"
            else if host.isLinux then
              "unknown-linux-gnu"
            else if host.isDarwin && host.isAarch64 then
              "apple-darwin"
            else if host.isDarwin && host.isx86_64 then
              "apple-darwin"
            else
              null;

          suffix = if variant == "gnu" || variant == "musl" then "" else "-${variant}";
        in
        if arch == null || targetTriple == null then
          throw "goose: unsupported platform ${system}"
        else
          "goose-${arch}-${targetTriple}${suffix}.tar.gz";

      # SHA256 hashes for all release tarballs
      hashFor =
        assetName:
        let
          hashes = {
            "goose-x86_64-unknown-linux-gnu.tar.gz" =
              "70532ea2ce7d38461cb670e696fa2b93674d16175ec393f2a954ef624161ff9d";
            "goose-x86_64-unknown-linux-musl.tar.gz" =
              "0ae8ed8f7e35c67fc85df416561b6fc416ef0fa3eaa344dca05e41472152682a";
            "goose-aarch64-unknown-linux-gnu.tar.gz" =
              "601242ad33fbbd70b3a72181aa1d449096f69b608152124ef16757019dec3ec0";
            "goose-aarch64-unknown-linux-musl.tar.gz" =
              "c62a6ea1f79df80c2809e836704c60e172f45b24db04f48e26720c1842f16b58";
            "goose-x86_64-apple-darwin.tar.gz" =
              "123364a43d295b2f33e245d4869ec6fe1e42991aee89e5eb41efee030e7578de";
            "goose-aarch64-apple-darwin.tar.gz" =
              "3c6b7cf321610dd8a20307ca76a4c75608fb5fe032d4f9fddf9ee1c761f1d4a9";
          };
        in
        hashes.${assetName} or (throw "goose: no hash for ${assetName}");

      # Build goose from a GitHub release tarball
      mkGoose =
        {
          system,
          variant ? "gnu",
        }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          asset = assetNameFor { inherit system variant; };
          src = pkgs.fetchurl {
            url = "https://github.com/aaif-goose/goose/releases/download/v${version}/${asset}";
            sha256 = hashFor asset;
          };
        in
        pkgs.runCommand "goose-${version}" { nativeBuildInputs = [ pkgs.bash ]; } ''
          mkdir -p $out/bin
          tar xzf ${src} -C $out/bin
          chmod +x $out/bin/goose
        '';

      # Convenience wrappers
      goose =
        system:
        mkGoose {
          inherit system;
          variant = "musl";
        };
      gooseGnu =
        system:
        mkGoose {
          inherit system;
          variant = "gnu";
        };
    in
    {
      packages = forAllSystems (system: {
        default = goose system;
        goose = goose system;
        goose-gnu = gooseGnu system;
      });

      overlays.default = final: prev: {
        goose = goose prev.stdenv.hostPlatform.system;
        goose-cli = goose prev.stdenv.hostPlatform.system;
        goose-gnu = gooseGnu prev.stdenv.hostPlatform.system;
      };
    };
}
