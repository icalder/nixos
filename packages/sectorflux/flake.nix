{
  description = "SectorFlux - Reverse proxy for monitoring and debugging local LLM agents";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation rec {
          pname = "sectorflux";
          version = "1.0.0";

          src = pkgs.fetchFromGitHub {
            owner = "particlesector";
            repo = "sectorflux";
            rev = "v${version}";
            hash = "sha256:0739biq1bqbi97zhlx68gqzx8y3ijjbga2vc5xgg1y2q418gyfsy";
          };

          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
            python3
            makeWrapper
          ];

          buildInputs = with pkgs; [
            asio
            crow
            sqlite
            httplib
            nlohmann_json
            openssl
          ];

          # Replace the project's CMakeLists.txt (which uses FetchContent) with our own
          # that uses system libraries.
          postPatch = ''
            cp ${./CMakeLists.txt} CMakeLists.txt
          '';

          postInstall = ''
            wrapProgram $out/bin/SectorFlux \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}
          '';

          meta.mainProgram = "SectorFlux";
        };
      }
    )
    // {
      overlays.default = final: prev: {
        sectorflux = self.packages.${prev.system}.default;
      };
    };
}
