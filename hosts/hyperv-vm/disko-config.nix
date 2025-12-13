{ lib, ... }:

let
  # Find the main disk device
  mainDisk = lib.head (lib.sort lib.lessThan (lib.attrNames lib.trivial.devices.disk));
in
{
  disko.devices.disk.${mainDisk} = {
    type = "disk";
    device = "/dev/${mainDisk}";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "defaults" ];
            label = "nixos";
          };
        };
      };
    };
  };
}