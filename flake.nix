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
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixos-wsl,
      home-manager,
      hello-world-server,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      system-aarch64 = "aarch64-linux";

      # Helper to generate package sets for different systems
      mkPkgs = system: config:
        import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.hello
            self.overlays.goodbye
            self.overlays.hello-world-server
          ];
          inherit config;
        };

      pkgs = mkPkgs system { };

      unstable-pkgs = import nixpkgs-unstable {
        inherit system;
        config = { };
      };

      pkgs-aarch64 = mkPkgs system-aarch64 {
        allowUnsupportedSystem = true;
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
            wsl.interop.register = true;
          }
        ];
      };

      nixosConfigurations.hyperv-vm = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          inherit unstable-pkgs;
        };
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/hyperv-image.nix"
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
          ./hosts/hyperv-vm/configuration.nix
        ];
      };

      nixosConfigurations.pi3a = nixpkgs.lib.nixosSystem {
        system = system-aarch64;
        specialArgs = {
          inherit unstable-pkgs;
        };
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          {
            # Tells Nix to cross-compile from your build host
            nixpkgs.buildPlatform = "x86_64-linux";
            nixpkgs.hostPlatform = "aarch64-linux";
            nixpkgs.pkgs = pkgs-aarch64;
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
          ./hosts/pi3a/configuration.nix
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

      packages.${system} = {
        hyperv-image = self.nixosConfigurations.hyperv-vm.config.system.build.image;
        pi3a-image = self.nixosConfigurations.pi3a.config.system.build.sdImage;
      };

    };
}
