{
  description = "Helper scripts for updating the Windows llama.cpp install";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      tools = pkgs: with pkgs; [
        bash
        gh
        curl
        unzip
        coreutils # comm, sort, wc, mktemp, date, cut, tail, mv
        findutils # find
        gnugrep   # grep
      ];
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "llama-cpp-update";
          packages = tools pkgs;
        };
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program =
            "${pkgs.writeShellScriptBin "update-llama-cpp" ''
              export PATH="${nixpkgs.lib.makeBinPath (tools pkgs)}:$PATH"
              exec "${./update-llama-cpp.sh}" "$@"
            ''}/bin/update-llama-cpp";
        };
      });
    };
}
