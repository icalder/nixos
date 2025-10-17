{
  description = "NixOS configurations";

  inputs = {
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-wsl.url = "github:nix-community/nixos-wsl/release-25.05";
    #hello-world-server.url = "git+file:///home/itcalde/rust/hello-world-server";
    hello-world-server.url = "github:icalder/hello-world-server";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-wsl,
      hello-world-server,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          self.overlays.hello
          self.overlays.goodbye
          self.overlays.hello-world-server
        ];
        config = { };
      };
    in
    {
      overlays.hello = import ./overlays/hello.nix;
      overlays.goodbye = import ./overlays/goodbye.nix;
      overlays.hello-world-server = import ./overlays/hello-world-server.nix {
        remotePkgs = hello-world-server.packages.${system};
      };

      # NB ".nixos" here is hostname
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;

        modules = [
          {
            nixpkgs.pkgs = pkgs;
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
          # Import the previous configuration.nix we used,
          # so the old configuration file still takes effect
          ./hosts/wsl/configuration.nix
          nixos-wsl.nixosModules.default
          {
            wsl.enable = true;
            wsl.defaultUser = "itcalde";
          }
        ];
      };
    };
}
