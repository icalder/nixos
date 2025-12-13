nix derivation show $(nix-instantiate fhs-test.nix)

# General Derivations
# Most standard derivations (like stdenv.mkDerivation, python3Packages.numpy, etc.) do not have .env—they just return their build outputs directly.

# The .env suffix is specific to environment-building utilities in nixpkgs that need to distinguish between "the wrapper" and "the environment definition."
nix-shell -E "(import ./fhs-test.nix {}).env"

# nix repl eval commands

pkgs = import <nixpkgs> { overlays = [(final: prev: { prev.callPackage ./fr24feed.nix {} })]; }

drv = pkgs.callPackage ./fr24feed-fhs.nix {}

pkgs = import <nixpkgs> {
            overlays = [(final: prev: {
              # Define fr24feed first
              fr24feed = prev.callPackage ./fr24feed.nix {};
              # Define fr24feed-fhs and ensure it uses the newly defined fr24feed
              fr24feed-fhs = final.callPackage ./fr24feed-fhs.nix {};
            })];
          }

pkgs.fr24feed-fhs.outputs