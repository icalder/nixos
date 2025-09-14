{
  description = "NixOS configurations";

  inputs = {
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-wsl.url = "github:nix-community/nixos-wsl/release-25.05";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-wsl,
      ...
    }@inputs:
    {
      # NB ".nixos" here is hostname
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
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
