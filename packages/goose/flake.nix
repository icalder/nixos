{
  description = "Goose CLI v1.35.0 — fetched from GitHub release tarballs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      version = "1.35.0";
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
              "b33f4f68f0bcaa898f42b7ae55f7bf790335e956ec0ec3342c5efb66c557a405";
            "goose-x86_64-unknown-linux-musl.tar.gz" =
              "f6e2592908d641a140e3f25a20cdd22ba6974be34797daa378e64702602b6775";
            "goose-aarch64-unknown-linux-gnu.tar.gz" =
              "19a08de20428d4a87939b6f10718ed73d64e878b96d95f18ceddc9110b3ccbc7";
            "goose-aarch64-unknown-linux-musl.tar.gz" =
              "280b2ae38d4679c48c943a28e3f7da836a63fecd2ac167c4bf3faa0566366707";
            "goose-x86_64-apple-darwin.tar.gz" =
              "315c31bf2fe7455b3f6a2ae3b1e12a0574b5d60fcf62317ff3ca16729ba012bd";
            "goose-aarch64-apple-darwin.tar.gz" =
              "89fa113ede792e6e4d5b73e3e9d4391dab9cc381395cd98d02029c986ddd1260";
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
