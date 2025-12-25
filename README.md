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
sudo nixos-rebuild switch
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

## Automatic Upgrades

```bash
systemctl status nixos-upgrade
journalctl -u nixos-upgrade.timer
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
    nix build .#k3s-server-image
    nix build .#k3s-agent-image
    ```
    This command will build the image and create a `result` symlink to the generated VHDX.

2.  The resulting VHDX image will be available in the `result` directory. You can then create a new **Generation 2** virtual machine in Hyper-V and use this VHDX as the existing hard disk.

3. Updates to the VM configuration, and rebuilds, can be done remotely with ssh access:

  ```bash
  # Build your new configuration from your flake and deploy it to the VM
  nixos-rebuild switch --flake /path/to/your/flake#hostname --sudo --target-host user@<VM-IP>
  nixos-rebuild switch --flake .#k3s-server --sudo --target-host itcalde@k3sserver
  nixos-rebuild switch --flake .#k3s-agent --sudo --target-host itcalde@k3sagent
  ```

4. To rebuild when logged into the vm, run:

  ```bash
  sudo nixos-rebuild switch --flake github:icalder/nixos#hyperv-vm
  ```

### Raspberry PI

To build an SD card image for use with a Pi 3A+:

1. Build the SD card image:

  ```bash
  nix build .#nixos-3a-image
  nix build .#alarmpi-image
  nix build .#rpi4-1-image
  ```

3. Write the image to the SD card:

   > **WARNING:** The `dd` command is a powerful tool that can overwrite any drive on your system. If you specify the wrong device, you could accidentally wipe your hard drive. Please be extremely careful and double-check the device name before running the command.

   a. Optional: Attaching the SD card in WSL2

      If you are running the `dd` command from WSL2, you will need to attach the SD card from Windows to WSL2. All of the following commands are run from PowerShell on the Windows host.

      > **WARNING:** These commands can cause data loss if you select the wrong disk. Please be extremely careful and double-check that you are selecting the correct disk for your SD card.

      **Attaching the device:**

      1.  Open **PowerShell** as **Administrator**.

      2.  List the available USB devices to find the BUSID of your SD card reader:

          ```powershell
          usbipd list
          ```

      3.  Bind the device to share it with WSL. Replace `<BUSID>` with the actual BUSID of your SD card reader.

          ```powershell
          usbipd bind --busid <BUSID>
          ```

      4.  Attach the device to WSL.

          ```powershell
          usbipd attach --wsl --busid <BUSID>
          ```
      
      After attaching, the SD card should appear as a block device in WSL. You can verify this by running `lsblk`.

      **Detaching the device:**

      When you are finished, detach the device.

      1.  Open **PowerShell**.

      2.  Detach the device using its BUSID.

          ```powershell
          usbipd detach --busid <BUSID>
          ```

   b. Identify your SD card:

      First, you need to identify the device name of your SD card. Insert the SD card into your computer and then run the following command to list the available block devices:

      ```bash
      lsblk
      ```

      Look for a device that matches the size of your SD card. It will likely be named something like `/dev/sda`, `/dev/sdb`, or `/dev/mmcblk0`. Make sure you have correctly identified the device name for your SD card before proceeding.

   c. Write the image to the SD card:

      Once you have identified the correct device name, you can use the following command to write the image to the SD card. The image is located in the `result` directory. Replace `/dev/sdX` with the device name of your SD card.

      ```bash
      zstdcat ./result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync oflag=direct status=progress
      ```

      **Command explanation:**

      *   `zstdcat ./result/sd-image/*.img.zst`: This decompresses the `.zst` file and sends the output to the pipe.
      *   `|`: This is the pipe, which sends the output of the `zstdcat` command to the `dd` command.
      *   `sudo dd of=/dev/sdX`: This writes the data to the SD card. `sudo` is required for write access to the device.
      *   `bs=4M`: This sets the block size to 4MB, which can speed up the writing process.
      *   `conv=fsync`: This ensures that all data is written to the SD card before the command completes.

   After the command finishes, the SD card will be ready to be used in your device.

#### Updates

Updates to the VM configuration, and rebuilds, can be done remotely with ssh access:

  ```bash
  # Build your new configuration from your flake and deploy it to the PI
  nixos-rebuild switch --flake .#nixos-3a --sudo --target-host itcalde@nixos-3a
  nixos-rebuild switch --flake .#alarmpi --sudo --target-host itcalde@alarmpi
  nixos-rebuild switch --flake .#opti --sudo --target-host itcalde@opti
  nixos-rebuild switch --flake .#rpi4-1 --sudo --target-host itcalde@rpi4-1
  ```

### Disk Size and Partitioning (Hyper-V)

You can control the disk size and partitioning scheme for your Hyper-V image within the `flake.nix` configuration.

#### Disk Size

The disk size is specified within the `nixosConfigurations.hyperv-vm` modules using the `virtualisation.diskSize` option. For example, to set the disk size to 20GB:

```nix
# In flake.nix, within the modules list for nixosConfigurations.hyperv-vm
nixosConfigurations.hyperv-vm = nixpkgs.lib.nixosSystem {
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

4.  **Importing the `disko` module and configuration** into the `modules` list for `nixosConfigurations.hyperv-vm` in `flake.nix`:

    ```nix
    # In flake.nix, within nixosConfigurations.hyperv-vm's modules section
    nixosConfigurations.hyperv-vm = nixpkgs.lib.nixosSystem {
      # ...
      modules = [
        "${nixpkgs}/nixos/modules/virtualisation/hyperv-image.nix"
        # ... existing modules
        disko.nixosModules.default
        ./hosts/hyperv-vm/disko-config.nix
      ];
    };
    ```