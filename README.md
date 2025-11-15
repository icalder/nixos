# NIXOS Configuration Stuff

## Key Links
https://nix.dev/tutorials/nix-language.html

https://search.nixos.org/packages
https://search.nixos.org/options

https://noogle.dev/

https://book.divnix.com/


## Symlinks

```bash
pushd /etc/nixos
sudo ln -sf /home/itcalde/nixos/flake.nix .
sudo ln -sf /home/itcalde/nixos/hosts .
```

## System Configuration

```bash
sudo nixos-rebuild switch
# sudo nixos-rebuild switch --flake .#nixos
sudo nixos-rebuild switch --rollback
sudo nixos-rebuild switch –-upgrade
sudo nixos-rebuild boot –-upgrade

nixos-rebuild list-generations
sudo nix-collect-garbage -d
sudo nix-collect-garbage –delete-older-than 7d
```

## Home Manager
https://github.com/nix-community/home-manager

https://nix-community.github.io/home-manager/options.xhtml

```bash

# update flake in ~/.config/home-manager to update to update home-manager inputs

home-manager generations
home-manager switch --flake ~/nixos#itcalde
home-manager switch –rollback
home-manager expire-generations "-1 day"
```

## Useful commands

`nix-store --query --requisites /run/current-system`

### why-depends

This command can be used to determine which package is causing curl to be installed, for example.

```bash
# Find the current location of the curl executable
curl_location=$(command -v curl)

# Get the real store path
curl_store_path=$(realpath "$curl_location")

echo "Curl store path: $curl_store_path"

nix why-depends /run/current-system "$curl_store_path"
```

## Virtual Machine Builds

This project supports building virtual machine images for different virtualization platforms.

### QEMU/KVM

To build and run a QEMU/KVM virtual machine:

1.  Build the VM:

    ```bash
    nixos-rebuild build-vm --flake .#qemu-vm
    ```

2.  Run the VM. The command above will create a script to run the VM. Execute it like this:

    ```bash
    ./result/bin/run-nixosvm-vm
    ```

### Hyper-V

To build a VHDX image for use with Microsoft Hyper-V:

1.  Build the VHDX image:

    ```bash
    nix build .#hyperv-image
    ```

2.  The resulting VHDX image will be available in the `result` directory. You can then create a new **Generation 2** virtual machine in Hyper-V and use this VHDX as the existing hard disk.

3. Updates to the VM configuration, and rebuilds, can be done remotely with ssh access:

  ```bash
  # Build your new configuration from your flake and deploy it to the VM
  nixos-rebuild switch --flake /path/to/your/flake#hostname --use-remote-sudo --target-host user@<VM-IP>
  ```

4. To rebuild when logged into the vm, run:

  ```bash
  sudo nixos-rebuild switch --flake github:icalder/nixos#hyperv-vm
  ```

### Disk Size and Partitioning (Hyper-V)

You can control the disk size and partitioning scheme for your Hyper-V image within the `flake.nix` configuration.

#### Disk Size

The disk size is now specified within the modules passed to `nixos-generators.nixosGenerate` using the `virtualisation.diskSize` option. For example, to set the disk size to 20GB:

```nix
# In flake.nix, within the modules list passed to nixos-generators.nixosGenerate
packages.${system}.hyperv-image = nixos-generators.nixosGenerate {
  # ...
  modules = [
    # ... other modules
    ({ config, pkgs, ... }: {
      virtualisation.diskSize = 20 * 1024; # 20GB
    })
  ];
};
```

#### Partitioning with Disko

For advanced and declarative partitioning, you can integrate `disko`. This involves:

1.  **Adding `disko` as an input in `flake.nix`**:

    ```nix
    # In flake.nix, under inputs
    inputs.disko.url = "github:nix-community/disko";
    ```

2.  **Adding `disko` to the `outputs` function arguments**:

    ```nix
    # In flake.nix, under outputs function arguments
    outputs = { self, nixpkgs, ..., disko }:
    ```

3.  **Creating a `disko` configuration file** (e.g., `hosts/vm/disko-config.nix`):

    ```nix
    # hosts/vm/disko-config.nix
    { lib, ... }:
    {
      disko.devices = {
        disk = {
          vda = {
            type = "disk";
            device = "/dev/sda"; # Or /dev/vda depending on Hyper-V settings
            content = {
              type = "gpt";
              partitions = {
                boot = {
                  size = "1G";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                root = {
                  size = "100%"; # Use remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                  };
                };
              };
            };
          };
        };
      };
    }
    ```

4.  **Importing the `disko` module and configuration** into the `modules` list passed to `nixos-generators.nixosGenerate` in `flake.nix`:

    ```nix
    # In flake.nix, within packages.${system}.hyperv-image's modules section
    packages.${system}.hyperv-image = nixos-generators.nixosGenerate {
      # ...
      modules = [
        (nixpkgs + "/nixos/modules/virtualisation/hyperv-guest.nix")
        # ... existing modules
        disko.nixosModules.default
        ./hosts/vm/disko-config.nix
      ];
    };
    ```