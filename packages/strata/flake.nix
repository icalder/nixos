{
  description = "Strata: a fast MoE inference engine for NVIDIA RTX 40/50 series GPUs (CUDA, sm_120)";

  inputs = {
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      # CUDA only; the engine is built for the host's Blackwell GPUs.
      supportedSystems = [ "x86_64-linux" ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # The CUDA 13 toolkit packages carry the NVIDIA EULA; allow exactly
      # those licenses (the same predicate the main flake uses).
      allowUnfreePredicate =
        pkg:
        let
          m = pkg.meta or { };
          licenses = m.licenses or (nixpkgs.lib.toList (m.license or []));
        in
        builtins.all
          (l: (l.free or true) || builtins.elem (l.shortName or "") [
            "CUDA EULA"
            "cuDNN EULA"
          ])
          licenses;

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = allowUnfreePredicate;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          strata = pkgs.callPackage ./strata.nix {
            # nvcc drives the host compiler; use the GCC it was validated with.
            stdenv = pkgs.cudaPackages_13.backendStdenv;
            cudaPackages = pkgs.cudaPackages_13;
          };
        in
        {
          default = strata;
          inherit strata;
        }
      );

      overlays.default = final: prev: {
        strata = self.packages.${prev.stdenv.hostPlatform.system}.strata;
      };
    };
}
