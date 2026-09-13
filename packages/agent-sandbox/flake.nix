{
  description = "Bubblewrap sandbox for coding agents (sandbox, sandbox-verify)";

  # No inputs: this sub-flake is only ever consumed through the root flake,
  # which provides nixpkgs via `inputs.nixpkgs.follows` (same as fr24feed and
  # adsbexchange). It is not buildable standalone, so no flake.lock is created.
  inputs = { };

  outputs =
    { self, nixpkgs, ... }:
    let
      # The script binds /lib64 (x86_64 dynamic linker); see SANDBOX-PACKAGING-PLAN.md F1
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        {
          default = nixpkgs.legacyPackages.${system}.callPackage ./default.nix { };
        }
      );

      overlays.default =
        final: prev:
        {
          agent-sandbox = self.packages.${final.stdenv.hostPlatform.system}.default;
        };
    };
}
