{
  description = "NixOS and Home Manager configurations";

  inputs = {
    # NixOS official package source, using the nixos-25.11 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixos-wsl.url = "github:nix-community/nixos-wsl/release-25.11";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs"; # Ensure consistent nixpkgs
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    #hello-world-server.url = "git+file:///home/itcalde/rust/hello-world-server";
    hello-world-server.url = "github:icalder/hello-world-server";
    ubc125.url = "github:icalder/ubc125";
    fr24feed = {
      url = "path:packages/fr24feed";
      # # url = "github:your-username/fr24feed-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    adsbexchange = {
      url = "path:packages/adsbexchange";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixos-wsl,
      agenix,
      home-manager,
      hello-world-server,
      ubc125,
      fr24feed,
      adsbexchange,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      system-aarch64 = "aarch64-linux";

      # Helper to generate package sets for different systems
      mkPkgs =
        system: config:
        import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.agenix
            self.overlays.hello
            self.overlays.goodbye
            self.overlays.hello-world-server
            self.overlays.ubc125
            fr24feed.overlays.default
            adsbexchange.overlays.default
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

      # Function to generate Hyper-V VM configuration
      mkHypervVm =
        extraArgs:
        let
          baseArgs = {
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
          # combine modules, don't replace
          combinedModules = baseArgs.modules ++ (extraArgs.modules or [ ]);

          # merge extraArgs over baseArgs, but keep combined modules
          finalArgs = (baseArgs // extraArgs) // {
            modules = combinedModules;
          };
        in
        nixpkgs.lib.nixosSystem finalArgs;

      # Function to generate Raspberry Pi (aarch64) system configuration
      mkPiSystem =
        extraArgs:
        let
          baseArgs = {
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
              agenix.nixosModules.default
              ./modules/autoupgrade.nix
            ];
          };

          # combine modules, don't replace
          combinedModules = baseArgs.modules ++ (extraArgs.modules or [ ]);

          # merge extraArgs over baseArgs, but keep combined modules
          finalArgs = (baseArgs // extraArgs) // {
            modules = combinedModules;
          };
        in
        nixpkgs.lib.nixosSystem finalArgs;
    in
    {
      overlays.agenix = final: prev: {
        agenix = agenix.packages.${final.stdenv.hostPlatform.system}.agenix;
      };
      overlays.hello = final: prev: {
        hello-script = prev.writeShellScriptBin "hello" "echo Hello World, how are you today!";
      };
      overlays.goodbye = final: prev: {
        goodbye-script = prev.writeShellScriptBin "goodbye" "echo Pa pa!";
      };
      overlays.hello-world-server = final: prev: {
        hello-world-server =
          hello-world-server.packages.${prev.stdenv.hostPlatform.system}.hello-world-server;
      };
      overlays.ubc125 = final: prev: {
        ubc125 = ubc125.packages.${prev.stdenv.hostPlatform.system}.ubc125;
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

      nixosConfigurations.hyperv-vm = mkHypervVm {
        modules = [
          { networking.hostName = "nixosvm"; }
        ];
      };

      nixosConfigurations.k3s-server = mkHypervVm {
        modules = [
          {
            networking.hostName = pkgs.lib.mkForce "k3sserver";
            boot.supportedFilesystems = [ "nfs" ];
            services.k3s = {
              enable = true;
              role = "server";
              token = "test-k3s-token";
              clusterInit = true;
              extraFlags = toString [
                "--write-kubeconfig-mode 644"
                "--default-local-storage-path /data"
                "--node-label \"nats-host=true\""
                "--node-label \"postgresql-host=true\""
              ];
            };
            systemd.tmpfiles.rules = [
              "d /data 0755 root root -"
            ];
          }
        ];
      };

      nixosConfigurations.k3s-agent = mkHypervVm {
        modules = [
          {
            networking.hostName = pkgs.lib.mkForce "k3sagent";
            boot.supportedFilesystems = [ "nfs" ];
            services.k3s = {
              enable = true;
              role = "agent";
              token = "test-k3s-token";
              serverAddr = "https://k3sserver:6443";
            };
            systemd.tmpfiles.rules = [
              "d /data 0755 root root -"
            ];
          }
        ];
      };

      nixosConfigurations.opti = nixpkgs.lib.nixosSystem {
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
          agenix.nixosModules.default
          ./hosts/opti/configuration.nix
          ./hosts/opti/changeip-update.nix
          ./modules/autoupgrade.nix
        ];
      };

      nixosConfigurations.nixos-3a = mkPiSystem {
        modules = [
          fr24feed.nixosModules.fr24feed
          ./hosts/nixos-3a/configuration.nix
        ];
      };

      nixosConfigurations.alarmpi = mkPiSystem {
        modules = [
          fr24feed.nixosModules.fr24feed
          ./hosts/alarmpi/configuration.nix
        ];
      };

      nixosConfigurations.rpi4-1 = mkPiSystem {
        modules = [
          ./hosts/rpi4-1/configuration.nix
          ./modules/autoupgrade.nix
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
        k3s-server-image = self.nixosConfigurations.k3s-server.config.system.build.image;
        k3s-agent-image = self.nixosConfigurations.k3s-agent.config.system.build.image;
        nixos-3a-image = self.nixosConfigurations.nixos-3a.config.system.build.sdImage;
        alarmpi-image = self.nixosConfigurations.alarmpi.config.system.build.sdImage;
        rpi4-1-image = self.nixosConfigurations.rpi4-1.config.system.build.sdImage;
      };

    };
}
