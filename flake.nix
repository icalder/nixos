{
  description = "NixOS and Home Manager configurations";

  inputs = {
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixos-wsl.url = "github:nix-community/nixos-wsl/release-25.05";
    #hello-world-server.url = "git+file:///home/itcalde/rust/hello-world-server";
    hello-world-server.url = "github:icalder/hello-world-server";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixos-wsl,
      home-manager,
      hello-world-server,
      nixos-generators,
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
      unstable-pkgs = import nixpkgs-unstable {
        inherit system;
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

        specialArgs = {
          inherit unstable-pkgs;
        };
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

      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          inherit unstable-pkgs;
        };
        modules = [
          {
            nixpkgs.pkgs = pkgs;
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
          ./hosts/vm/configuration.nix
        ];
      };

      # Home Manager configuration for user "itcalde"
      homeConfigurations.itcalde = home-manager.lib.homeManagerConfiguration {
        inherit pkgs; # Using the same pkgs as NixOS for consistency

        extraSpecialArgs = {
          inherit unstable-pkgs;
        };
        # The path to your home.nix is now relative to the root flake.
        modules = [ ./home-manager/home.nix ];
      };

      packages.${system}.hyperv-image = nixos-generators.nixosGenerate {
        inherit system;
        format = "hyperv";
        specialArgs = {
          inherit unstable-pkgs;
        };
        modules = [
          {
            nixpkgs.pkgs = pkgs;
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
          {
            virtualisation.diskSize = 20 * 1024; # 20GB
          }
          ./hosts/vm/configuration.nix
        ];

      };
    };
}
